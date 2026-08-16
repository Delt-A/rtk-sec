# rtk-sec

Security-tool output filters for [rtk](https://github.com/rtk-ai/rtk).

rtk ships ~63 filters, all of them for dev/infra tooling. Pentest tools are the
noisiest thing a terminal produces — ASCII banners, `\r` progress repaints,
hundreds of `Rejected`/`STATUS`/404 lines — and none of them were covered.
rtk-sec adds filters for 13 of them, plus a wrapper for the five whose output
needs counting rather than line-filtering.

## Install

```bash
./install.sh
```

Idempotent. Backs up `~/.config/rtk/filters.toml`, merges a managed block,
trusts it, and gates on `rtk verify --require-all` — restoring the backup if any
inline test fails. `./install.sh --dry-run` prints the merged result and touches
nothing. `./uninstall.sh` reverses everything.

Nothing else to configure: rtk's PreToolUse hook picks up user-defined filters
automatically, so `gobuster …` is rewritten to `rtk gobuster …` transparently.

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

The lab has nine findings and a 4614-word wordlist. Real targets skew the ratio
further: the banner is a fixed cost and the progress/noise scales with the scan,
so a large `ffuf` or `nuclei` run saves considerably more than this table shows.

## Safety model

Filtering security output has one failure mode that matters: hiding a finding,
or worse, making a scan that never ran look like a scan that found nothing.
Three rules follow from that.

**Keep vs strip is not a style choice.** `keep_lines_matching` is used only
where findings have a rigid machine-generated shape (gobuster, ffuf,
feroxbuster, nuclei, netexec, hydra, wafw00f). Where findings are free-form and
only the *noise* is rigid, the filter strips instead (nikto, sqlmap, sslscan,
john, impacket, whatweb). john is the clearest case — a cracked line is
`password123      (alice)`, with no prefix to match on.

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

rtk's own tee is **not** a safety net here: measured on 0.45.0, it fires only
when the wrapped command exits non-zero, regardless of `[tee] mode = "always"`.
A successful scan is never teed. So:

- `~/.claude/rtk-sec.md` (installed automatically) instructs Claude to pass each
  tool's native output flag — `gobuster -o`, `ffuf -o … -of json`, `nuclei -o`.
  These artifacts are better than a tee: structured and machine-readable.
- `bin/rtk-sec` **always** tees the raw stream and prints `[full output: <path>]`,
  for the five tools it wraps.

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
| **Validated against real captured output** | gobuster, ffuf, feroxbuster, nikto, sqlmap, whatweb, wafw00f |
| **Format stable, inline-tested only** | nuclei, sslscan, hydra, netexec, john, impacket |
| **Not shipped** | testssl (not installed here, format unverified) |

testssl is deliberately absent: shipping a guessed regex risks hiding a finding,
which is exactly what the safety model exists to prevent.

The sqlmap filter was written against a real run rather than from memory —
`lab/vuln-sqli.py` is a loopback-only, deliberately injectable target that exists
so sqlmap emits a genuine `Parameter:/Type:/Title:/Payload:` block to design
against. That block, including the full UNION payload, passes through untouched;
`truncate_lines_at` is 400 so a payload is never cut mid-`CHAR()`.

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
