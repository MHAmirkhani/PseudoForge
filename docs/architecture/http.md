# The website

The website is a **fourth interface**, not a second project. It calls the same
functions the command line calls, through the same contract, and it can
therefore never answer a question differently from `pseudoforge`.

```text
                    ┌─────────────────────────┐
                    │      lib/ (core)        │
                    │  engines · formats ·    │
                    │  validate · convert ·   │
                    │  recipes · profiles     │
                    └─────────────────────────┘
                                │
                      ┌─────────┴─────────┐
                      │   sink contract   │
                      │  pf_emit / pf_*   │
                      └─────────┬─────────┘
                                │
        ┌──────────┬────────────┼────────────┬──────────┐
        ▼          ▼            ▼            ▼          ▼
    ┌───────┐  ┌───────┐    ┌───────┐    ┌───────┐  ┌───────┐
    │  CLI  │  │  TUI  │    │ JSON  │    │ REST  │  │  ...  │
    └───────┘  └───────┘    └───────┘    └───────┘  └───────┘
```

## Where the API actually lives

`lib/http.sh`. The route table, the handlers, the response shapes and the
refusals are all in Bash, with the rest of the core.

The HTTP server is a **transport**:

```text
HTTP request  →  pseudoforge api <METHOD> <PATH> [body]  →  HTTP response
```

`server/app.py` moves bytes and a status code. It has no business logic, and a
test asserts it: if `app.py` ever decided something about conversion kinds, or
answered an endpoint itself, the suite fails.

!!! abstract "The rule"
    If a piece of logic exists only in the website, it belongs in `lib/`.

That is why the route table is also what generates
[the API reference](../reference/http-api.md) and what
`GET /api/routes` returns. One table, three consumers, no third opinion.

### What that buys

`GET /api/health` is `doctor_checks` rendered as JSON — the same records the
CLI prints and the wizard panels. A test compares the count from the endpoint
against `pseudoforge doctor --json` and fails if they differ, because a
divergence there would mean the endpoint had started doing its own checking.

`POST /api/convert` delegates to `cvt_convert`. The handler looks up the
conversion's *kind* only to choose a status code — 409 for a refusal, 503 for a
missing tool, which are HTTP concerns — and the judgement about whether the
conversion is possible is taken once, in the core.

## Why the VPS does not run engines

The deployment target is **1 core, 1 GB of RAM, 10 GB of disk**. It does not
have the nine engines, Quantum ESPRESSO, GSL, LAPACK, cmake or ninja, and it is
not going to.

This is the architecture, not a limitation being worked around.

- **Generation is minutes of CPU and hundreds of MB of RAM per element.** One
  core serving a web front end cannot do it while remaining a web front end.
- **The engines are a build problem, not a runtime one.** Several need patched
  source trees and a Fortran toolchain. Putting that on a public server means
  maintaining a compiler estate to serve files.
- **The answer would be worse than no answer.** A queue whose workers do not
  exist looks like it is working. A user waits, and nothing ever arrives.

So the split is:

| | Runs where | Why |
|---|---|---|
| **Generation** | your machine | it needs the engines, and you have them |
| **Serving pre-built files** | the VPS | that is what a small server is good at |
| **Conversion** | the VPS | the converters are small and need no toolchain |
| **Validation** | the VPS | the structural checks need no engine |

`POST /api/generate` answers **501**:

```json
{
  "error": "generation_not_available_here",
  "message": "Generation runs on your machine, not on this server.",
  "instructions": "Install PseudoForge and run: pseudoforge generate ...",
  "install_url": "https://pseudo.amirkhani.me/docs/getting-started/installation/"
}
```

Refusing and saying what to do instead is the honest answer. The frontend turns
that response into a copyable command and a link to the installation page.

## Why FastAPI, and what that means

Two options were on the table: a small Bash HTTP server (`websocketd`,
`socat`, `ncat`), or FastAPI calling `pseudoforge api` as a subprocess.

**FastAPI**, because:

- The hard parts of HTTP — multipart uploads, streaming file responses,
  concurrent connections, correct status handling — are solved there and would
  be hand-rolled in Bash.
- The transport is ~250 lines with no logic in it. A Bash server would be more
  code doing less.
- Python is already a **documented external dependency** of the same kind as
  gnuplot and matplotlib: used when present, never required, and never part of
  the core.

!!! note "Bash-only still holds"
    Nothing in `lib/` imports Python. The command line, the wizard and
    `pseudoforge api` all work identically on a machine with no Python at all.
    The rule was never "no Python anywhere" — it is that **the core is Bash**,
    and external tools are reached through `PATH`.

## The served tree

```text
/var/lib/pseudoforge/
  native/           ~1 GB     pre-built files, one format per engine
  converter/        ~100 MB   upfconv.x
  cache/            ~1-2 GB   LRU cache of conversions
  db/pseudoforge.db ~100 MB   SQLite metadata
  docs/             ~50 MB    the built MkDocs site
  www/              ~10 MB    the frontend
```

About 3.3 GB planned, against an 8 GB budget on a 10 GB disk.
`tests/test_vps_layout.sh` asserts it, and also asserts that the installer
pulls in no compiler and builds no engine — because the first symptom of that
having changed, on a real deployment, is a full disk.

### One source of truth, two derived views

```text
the files on disk           ← the truth
    ↓  pseudoforge native index   (reads each file's provenance sidecar)
native/index.tsv            ← what lib/http.sh reads
    ↓  deploy/scripts/load-index.sh
SQLite native_files         ← what the server queries without a filesystem scan
```

The database is a cache of a derivation, never an independent record. It can be
rebuilt from the files at any time, and an attribute that is not in a file's
provenance is reported as `unknown` rather than guessed — a guessed functional
on a pseudopotential is the kind of error that survives into someone's paper.

## Degrading

Same contract as `doctor`. If a converter is not installed, the endpoint says
which one and returns 503; it does not pretend, and it does not fall back to
something else:

```json
{
  "error": "converter_unavailable",
  "message": "The tool for van to upf is not installed on this server.",
  "tool": "upfconv"
}
```

And a refusal carries the core's reason, in full, rather than a generic error:

```json
{
  "error": "conversion_refused",
  "from": "vps", "to": "upf", "kind": "refused",
  "reason": "An OpenMX .vps holds semilocal potentials V_l(r) ... a new pseudopotential, not a relabelled file."
}
```

## A possible extension: queue and worker

If generation on demand is ever wanted, the shape that would work — and which
is deliberately **not** implemented — is:

```text
  browser → POST /api/jobs        → job queued in SQLite, 202 Accepted
  worker  → GET  /api/jobs/next   → claims a job   [on a machine with engines]
  worker  → runs pseudoforge generate
  worker  → POST /api/jobs/:id/result  → uploads the files
  browser → GET  /api/jobs/:id    → done, here is the download
```

The worker is a **separate machine** — a workstation, a CI runner, a burst VM —
that has the engines and polls for work. The VPS stays a queue and a file
store, which is what it is good at.

What would have to be built: job records and state transitions, worker
authentication, result upload with integrity checking, retention and cleanup,
and an honest answer for "no worker has collected this job in an hour".

That last one is the reason it is not here yet. **A queue with no workers is
worse than a refusal**, because it looks like it is working. Until there is a
worker that reliably exists, 501 is the truthful answer, and the truthful
answer is the one this project ships.

## Adding a fifth interface

Write a sink, install it, call the same functions:

```bash
pf_sink_use json
pf_config_load
cmd_generate
```

See [the sink contract](sink-contract.md). The REST interface is the worked
example: `lib/http.sh` is 500 lines, and none of them re-implements anything.
