# rtk-sec

Security-tool output filters for [rtk](https://github.com/rtk-ai/rtk).

rtk ships ~63 filters, all of them for dev/infra tooling. Pentest tools are the
noisiest thing a terminal produces — ASCII banners, `\r` progress repaints,
hundreds of `Rejected`/`STATUS`/404 lines — and none of them were covered.
rtk-sec adds filters for 16 of them, plus a wrapper for the five whose output
needs counting rather than line-filtering.

## Prerequisite: rtk itself

`./install.sh` only adds filters to an rtk that's already there — it checks
for the binary and refuses to run without it (`rtk not found — install it
first`). If `rtk --version` doesn't already work:

```bash
curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/master/install.sh | sh
```

Apache-2.0 edition (no BUSL-licensed compression engine) instead:

```bash
curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/master/install.sh | RTK_EDITION=oss sh
```

Windows: `winget install rtk-ai.rtk`.

**Verify it's the right `rtk`** — a same-named, unrelated Rust tool
(`reachingforthejack/rtk`, "Rust Type Kit") exists on crates.io and
`cargo install rtk` can grab it by mistake:

```bash
rtk gain    # must print a token-savings dashboard, not "command not found"
```

If `rtk --version` works but `rtk gain` doesn't, that's the wrong rtk —
`cargo uninstall rtk` and reinstall from the command above. rtk-sec's own
`install.sh` additionally requires **rtk ≥ 0.45.0**; it checks this itself
and exits with a clear error if the version is too old.

## Install rtk-sec

```bash
./install.sh
```

Idempotent. Backs up `~/.config/rtk/filters.toml`, merges a managed block,
trusts it, and gates on `rtk verify --require-all` — restoring the backup if any
inline test fails. `./install.sh --dry-run` prints the merged result and touches
nothing. `./uninstall.sh` reverses everything.

Nothing else to configure: rtk's PreToolUse hook picks up user-defined filters
automatically, so `gobuster …` is rewritten to `rtk gobuster …` transparently.

Note: rtk-sec only ships *filters* — it doesn't install the pentest tools
themselves. `gobuster`, `nmap`, `sqlmap`, `tshark`, etc. still need to be on
the target machine for their own filter to do anything.

## Measured savings

Against real output captured from the loopback lab (`lab/`):

| Tool | raw | filtered | saved |
|---|---:|---:|---:|
| wafw00f | 914 | 137 | **85%** |
| ffuf | 4492 | 1222 | **72%** |
| sqlmap | 4225 | 1376 | **67%** |
| nikto | 3043 | 1414 | **53%** |
| gobuster | 1362 | 701 | **48%** |
| whatweb | 279 | 148 | **46%** |
| feroxbuster | 2798 | 1543 | **44%** |
| smbclient | 415 | 378 | **8%** |
| nmap | 931 | 863 | **7%** |
| tshark (live capture) | 502 | 474 | **5%** |
| tshark (`-r`, reading a file) | 3756 / 88 | 3756 / 88 | **0%** |

The lab has nine findings and a 4614-word wordlist. Real targets skew the ratio
further: the banner is a fixed cost and the progress/noise scales with the scan,
so a large `ffuf` or `nuclei` run saves considerably more than this table shows.
nmap and smbclient are the opposite case — both already print a compact,
line-dense result with almost no machinery to strip, so the honest number is
single-digit. They're included anyway because they're real tools this
project's own session history showed were in actual use with zero filter
coverage; a smaller, honest saving beats no filter.

tshark is the extreme version of that same honesty: `-r <file>` — the mode
this project's own history actually used (`tshark -r capture.pcapng -Y http
-T fields …`) — has **no boilerplate at all**. Every line is a packet, a
field, or an error. The filter is a correct, verified no-op there, and the
table says so rather than reporting the unrelated 5% from live-capture mode
as if it applied generally.

## Safety model

Filtering security output has one failure mode that matters: hiding a finding,
or worse, making a scan that never ran look like a scan that found nothing.
Three rules follow from that.

**Keep vs strip is not a style choice.** `keep_lines_matching` is used only
where findings have a rigid machine-generated shape (gobuster, ffuf,
feroxbuster, nuclei, netexec, hydra, wafw00f). Where findings are free-form and
only the *noise* is rigid, the filter strips instead (nikto, sqlmap, sslscan,
john, impacket, whatweb, nmap, smbclient). john is the clearest case — a
cracked line is `password123      (alice)`, with no prefix to match on. nmap
is the same shape for a different reason: NSE vulnerability-script findings
print as `| scriptname:` / `|_scriptname:`, a prefix no noise line in nmap's
own output ever produces, so there's nothing a keep-list could usefully
anchor on without being a no-op.

tshark pushes this to its logical end: in `-r` mode there is no noise at
all, so strip-mode with exactly one pattern (the live-capture startup
banner) is correct, and it's a deliberate no-op for the file-reading mode
that's actually the common case. A packet-count line (`N packets captured`)
is kept on purpose rather than stripped as "boilerplate" — in `-w file.pcap`
mode it's the only stdout line at all, and 0 vs N packets is itself the
finding (did the capture filter, interface, or permissions actually work).

**Every keep-list carries error patterns.** `(?i)^error`, `connection refused`,
and per-tool fatals are mandatory, enforced by `tools/check-collisions.sh` in
CI. Every filter also has an inline test asserting a specific failure is *not*
swallowed. This is verified end-to-end against dead ports, not just in unit
tests.

**`on_empty` never claims absence.** The wording is always *"no X matched the
filter (see full output)"*, because a filter cannot distinguish "the tool found
nothing" from "my regex matched nothing".

`match_output` — which replaces the entire output with one line — is banned in
v1 and the CI lint rejects it.

### Preserving full output

Two separate rtk tee mechanisms exist, confirmed by direct testing (both
0.45.0 and 1.0.1), and they behave differently:

- **The general `[tee] mode = "always"` config is not a safety net here.**
  Verified: a small, well-under-`max_lines`, exit-0 scan produces no tee file
  at all despite `mode = "always"`. It only fires when the wrapped command
  exits non-zero, so a *successful* scan with findings is never preserved by
  this mechanism alone.
- **`max_lines` truncation has its own, always-on tee, independent of exit
  code.** When a TOML filter's `max_lines` actually drops lines, rtk appends
  `... (N lines truncated)` *and* `[see remaining: tail -n +101 <tee file>]`
  — verified byte-for-byte identical to the untruncated original on both rtk
  versions. This means every one of rtk-sec's 16 TOML filters already has a
  built-in recovery path for the one case where line-capping could plausibly
  cut a real finding.

Neither mechanism preserves output for the five `bin/rtk-sec`-wrapped tools,
since their *summary* is produced by Python, not by a TOML `max_lines` cap.
So:

- `~/.claude/rtk-sec.md` (installed automatically) instructs Claude to pass each
  tool's native output flag — `gobuster -o`, `ffuf -o … -of json`, `nuclei -o`.
  These artifacts are better than a tee: structured and machine-readable.
- `bin/rtk-sec` **always** tees the raw stream itself and prints
  `[full output: <path>]`, for the five tools it wraps — this is why that
  wrapper exists independently of either rtk mechanism above.

### Truncation inside the wrapper

`Grouped` (`ffuf`, `feroxbuster`) used to cap each status group at 8 labels
with a `(+N more)` marker. **Removed** — a count the agent can't act on
without a second read of the tee file defeats the point of a summary, and a
user asking "does the AI actually see all 10, or 8 + a number?" made clear
that silent capping is a real cost even when labelled. The per-status lists
in `rtk-sec ffuf`/`rtk-sec feroxbuster` output are now the full, authoritative
count — no cap, no marker needed because there's nothing left to mark.

Three other summarisers still cap, for a different reason: they're a *log
tail* (hashcat's live-progress display, error dedup, netexec's informational
host lines), not a findings list — unbounded would mean printing noise, not
missed results. Each of these is now labelled when it actually truncates,
after an audit found all three capping silently with no marker:
`error_block()` (errors beyond 10), `Netexec`'s `[*]` info lines (beyond 10),
and the base `Summary.render()` tail (beyond the last 40 lines). None of these
ever dropped data from the `[full output: <path>]` tee file — the tee always
wrote every raw line — the gap was only in the *terminal summary*
under-reporting without saying so.
Two things never get capped, by design: `Netexec`'s `[+]` "Pwn3d!" successes,
and hashcat's `--show` follow-up (every cracked credential is printed, since
that is the one output a crack run exists to produce).

## The rtk-sec wrapper

For tools whose output needs counting, not line-filtering:

```bash
rtk-sec ffuf -u http://target/FUZZ -w wordlist.txt
```
```
11 hits — 200: 4  301: 7
  [200] , cgi-bin/, index.html, .git/HEAD
  [301] admin, backup, cgi-bin, css, icons, images, js
[full output: ~/.local/state/rtk-sec/20260816-183013-ffuf-889495.log]
```

| Tool | Why a wrapper |
|---|---|
| ffuf | inject `-noninteractive`; group hits by status |
| feroxbuster | inject `--no-state` (stops `.state` files in cwd); group by status |
| nuclei | inject `-silent -nc`; group by severity, dedupe templates across hosts |
| netexec / nxc / cme | collapse N failures to `40/41 hosts: STATUS_LOGON_FAILURE`, hoist `(Pwn3d!)` |
| hashcat | inject `--quiet`; run `--show` afterwards for cracked pairs |

The exit code is always the tool's. The child runs with `RTK_DISABLED=1` so a
tool is either on the TOML path or the wrapper path, never filtered twice. The
tee is line-buffered, so a `kill -9` still leaves a usable file, and the pointer
line is printed from a `finally:` block.

Note: ffuf's `-s` is deliberately *not* injected — silent mode strips the
Status/Size metadata the summary groups on.

## Confidence

| Level | Tools |
|---|---|
| **Validated against real captured output** | gobuster, ffuf, feroxbuster, nikto, sqlmap, whatweb, wafw00f, nmap, smbclient, tshark |
| **Format stable, inline-tested only** | nuclei, sslscan, hydra, netexec, john, impacket |
| **Not shipped** | testssl (not installed here, format unverified) |

testssl is deliberately absent: shipping a guessed regex risks hiding a finding,
which is exactly what the safety model exists to prevent.

The sqlmap filter was written against a real run rather than from memory —
`lab/vuln-sqli.py` is a loopback-only, deliberately injectable target that exists
so sqlmap emits a genuine `Parameter:/Type:/Title:/Payload:` block to design
against. That block, including the full UNION payload, passes through untouched;
`truncate_lines_at` is 400 so a payload is never cut mid-`CHAR()`.

nmap and smbclient came from the same discipline applied one step earlier:
rather than guessing which pentest tools this project's users actually run,
`lab/nmap-targets.py` (loopback TCP listeners with banners) and a loopback
`impacket-smbserver` share were stood up to capture real `-sV` and
`recurse; ls` output, plus the real `NT_STATUS_*`/`Note: Host seems down`
error strings, before either filter was written.

## Development

```bash
./tools/build-filters.sh      # filters/**/*.toml -> dist/ and .rtk/ (with TOML + test-coverage checks)
./tools/check-collisions.sh   # name collisions vs rtk builtins, mandatory error patterns
rtk verify                    # run every inline test
./tools/replay-test.sh        # end-to-end against real captured output
./lab/serve.sh 8080           # loopback-only HTTP target for capturing new samples
./lab/vuln-sqli.py 8081       # loopback-only injectable target (sqlmap samples)
```

`rtk verify` only discovers inline tests in a **project-local** `.rtk/filters.toml`,
never the global one — which is why `build-filters.sh` writes both.

`tools/replay-test.sh` shadows the tool on `PATH` with a stub that replays a
captured sample, so rtk reconstructs the real command and matches
`match_command` exactly as it would in a live run. This is the only way to
exercise the `\r`/ANSI/stderr behaviour that inline tests (which take clean
string literals) cannot reach.

Sample capture is loopback-only by construction. `lab/serve.sh` binds to
127.0.0.1 and seeds paths that common wordlists contain. No third-party host is
ever scanned.

## Filter DSL notes

Established empirically against rtk 0.45.0:

- `replace` runs **before** `keep_lines_matching`/`strip_lines_matching`. This
  is what makes `{ pattern = "(?m)^.*\\r", replacement = "" }` work: it collapses
  each physical line to its final repaint. ffuf packs many progress repaints and
  the finding onto one physical line, with the finding after the last `\r`.
- `$1` capture groups work in `replacement`.
- `keep_lines_matching` is an unanchored substring match.
- `max_lines` appends `... (N lines truncated)`; `truncate_lines_at` is the
  **total** width including the `...` suffix.
- `on_empty` fires both when the tool output nothing and when the filter emptied
  it — the two are indistinguishable, hence the wording rule above.
- An invalid regex disables only that one filter (with a stderr warning); it
  does not poison the file.
- The user-global `filters.toml` is inert until `rtk trust -y` is run.

`match_command` is deliberately narrow — it requires a real scan invocation
(`^gobuster\s+(dir|dns|vhost|…)`, `^ffuf\b.*\s-u\s`) rather than just the tool
name. A keep-mode filter matching `gobuster --version` would swallow the version
string entirely and point at a full-output file that does not exist, since rtk
does not tee on success.
