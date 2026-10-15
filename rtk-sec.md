# rtk-sec — security tool output filters

`rtk` filters these tools automatically (the PreToolUse hook rewrites
`gobuster …` to `rtk gobuster …` with no action needed). Output is condensed;
findings and errors are preserved.

## Always write full output to a file

rtk's own tee **only fires when a command exits non-zero**, so a successful scan
is never preserved. Use the tool's native output flag on every real scan — the
artifact is better than a tee anyway (structured, machine-readable):

| Tool | Flag |
|---|---|
| gobuster | `-o out.txt` |
| ffuf | `-o out.json -of json` |
| feroxbuster | `-o out.txt` |
| nuclei | `-o out.txt` (or `-j -o out.jsonl`) |
| nikto | `-o out.txt` |
| sqlmap | writes to `~/.local/share/sqlmap/output/` by default |
| netexec | `--log out.txt` |
| hashcat | uses its potfile; `--show` re-reads it |
| nmap | `-oN out.txt` (or `-oA out` for all three formats) |
| smbclient | no native log flag; redirect stdout yourself if the share is large |
| tshark | `-w out.pcapng` to a file, then `-r out.pcapng` to re-analyze |

When a filtered result looks thin or surprising, read that file rather than
re-running the scan.

## Quiet flags worth adding

`gobuster -q --no-progress` · `sqlmap --batch -v 0 --disable-coloring` ·
`wpscan --no-banner` · `nuclei -silent` · `nikto -nointeractive`

nmap's own output is already compact — there's no quiet flag to add, and the
filter only strips `-v`/NSE timing lines, which are low-value either way.

tshark in `-r` (reading a capture file) mode has no filter applied at all —
there's no boilerplate to strip in that mode, only packets, fields, and
errors, all of which are real data. Only `-i` (live capture) gets its
startup banner dropped; the packet-count line is always kept.

These cut noise at the source; the filters are there for when they are forgotten.

## Long-running tools

rtk buffers the whole output and prints nothing until the command exits. For
`responder`, long `hydra` runs, or a full `nuclei` template set, wrap in
`timeout`: `timeout 300 rtk nuclei -u http://target`. Without it a Bash-tool
timeout loses the output entirely.

## rtk-sec wrapper (aggregation)

Five tools also have a wrapper that groups findings and **always** tees the raw
stream, printing `[full output: <path>]`:

```bash
rtk-sec ffuf -u http://target/FUZZ -w wordlist.txt
```

Available for `ffuf`, `feroxbuster`, `nuclei`, `netexec`/`nxc`/`crackmapexec`,
`hashcat`. Use it for wide scans; use plain `rtk <tool>` otherwise.

## Reading filtered output

- `no X matched the filter (see full output)` means **the filter matched
  nothing**, not that the tool found nothing. Check the raw file before
  concluding a target is clean.
- Errors are never filtered out. If a scan shows no findings and no error,
  it genuinely returned nothing.
