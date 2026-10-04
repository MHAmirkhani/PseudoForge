# Architecture

PseudoForge is a core library with interchangeable front ends. The core does
the work; an interface decides how the result looks.

```
┌──────────────────────────────────────────────────────────┐
│                       lib/  (core)                       │
│   engines · formats · validate · convert · recipes       │
│   profiles · metadata · report · params · sink           │
│                                                          │
│   returns:  data on stdout · status as exit code         │
│             messages through pf_emit                     │
└──────────────────────────────────────────────────────────┘
        │                   │                   │
        ▼                   ▼                   ▼
┌───────────────┐   ┌───────────────┐   ┌───────────────┐
│      CLI      │   │      TUI      │   │    Web API    │
│ pf_sink_cli   │   │ pf_sink_      │   │ pf_sink_json  │
│ pf_confirm_   │   │   capture     │   │ pf_confirm_   │
│   tty         │   │ pf_confirm_   │   │   assume      │
│               │   │   assume      │   │               │
│ prints        │   │ renders panel │   │ serialises    │
└───────────────┘   └───────────────┘   └───────────────┘
```

## The contract

Three channels, and every core function uses the same three.

| channel | carries | mechanism |
|---|---|---|
| **data** | the result | stdout, structured records — tab-separated fields, one per line |
| **status** | did it work | exit code: `0` success, non-zero failure |
| **messages** | what happened | `pf_emit <level> <message>` → the installed sink |

**No module in `lib/` may write to a terminal or read from one.** A test
asserts this: no `>&2`, no `read`, in any core module.

## Why a sink rather than return values

There are 551 reporting calls across seven verbs in `lib/`. They already
funnelled through a single `_log`, so replacing that one function decoupled the
whole core at once.

Threading status upward through every function signature would have touched all
28 modules, risked a silent behaviour change in each, and bought nothing the
sink does not already provide. The verbs — `info`, `ok`, `warn`, `error`,
`debug`, `banner` — kept their names and arguments. What changed is that they
no longer decide where anything goes.

## Sinks

| sink | used by | behaviour |
|---|---|---|
| `pf_sink_cli` | CLI (default) | prints to stderr, colours, honours `PF_QUIET`/`PF_VERBOSE` |
| `pf_sink_capture` | TUI, tests | records to `PF_SINK_RECORDS`, prints nothing |
| `pf_sink_json` | web API | one JSON object per line on stdout |
| `pf_sink_null` | batch | discards |

Install one with `pf_sink_use cli|capture|json|null`, or set `PF_SINK`
directly. The default is `pf_sink_cli`, so a script that loads the core and
calls nothing else behaves exactly as it always did.

Captured records are queried as data, not scraped as text:

```sh
pf_sink_reset
some_core_operation
pf_sink_count error      # how many errors
pf_sink_filter warn      # the warning messages
pf_sink_failed           # exit status: did anything fail
```

The JSON sink emits one object per line rather than a single array, so a long
operation streams instead of buffering, and a truncated response is still
parseable up to the cut.

## Asking the user

A core module must never prompt. Two of them used to: `build.sh` asked before
installing packages, `executor.sh` asked before generating missing elements.
Both read the terminal directly. On a CLI that is merely impolite; behind a web
API it hangs the request, and in a test it hangs the suite.

`pf_confirm <question>` asks the *interface* to ask:

| hook | behaviour |
|---|---|
| `pf_confirm_tty` | prompts on the terminal (CLI, default) |
| `pf_confirm_assume` | never asks; answers from `PF_ASSUME` |

`pf_confirm_tty` returns "no" when there is no terminal, because the questions
it guards are installs and overwrites.

## The CLI is the reference implementation

Every operation is reachable from the CLI first, then exposed in the TUI and
the web API. If something can only be done through the TUI, that is a bug: it
means logic lives in the interface that belongs in the core.

## Adding an interface

1. Install a sink: `pf_sink_use json`, or write your own `pf_sink_*` function.
2. Install a confirmation hook: `pf_confirm_use assume` and set `PF_ASSUME`.
3. Call core functions. Read their data from stdout, their status from the exit
   code, and their messages from the sink.
4. Change nothing in `lib/`.

Step 4 is the test of whether the separation holds.

## Module map

| module | responsibility |
|---|---|
| `core.sh` | reporting verbs, small utilities |
| `sink.sh` | where messages go; who asks the user |
| `config.sh` | defaults and `~/.pseudoforgerc` |
| `elements.sh`, `xc.sh` | element and functional registries |
| `profiles.sh`, `params.sh` | libraries and their published inputs |
| `engines.sh`, `build.sh` | the nine generators and how to compile them |
| `recipe.sh`, `input_builder.sh` | turning settings into an engine's input deck |
| `executor.sh`, `run.sh` | running an engine, auto-fix retries, batching |
| `validate.sh`, `testing.sh` | per-engine transferability and cutoff scans |
| `convert.sh` | format conversion, with reasoned refusals |
| `upf.sh`, `formats.sh` | output formats and their validators |
| `report.sh`, `metadata.sh` | reports, provenance, citations |
| `cli.sh`, `ui.sh`, `wizard.sh` | **interfaces** — the only modules that render |

---

## Where to go from here

| Document | Covers |
|---|---|
| [The sink contract](sink-contract.md) | `pf_emit`, the three channels, what a core module may not do |
| [The engine interface](engine-interface.md) | what an engine must provide, and how nine are driven by one core |
| [Validation](validation.md) | the three checks, the grading scale, failure isolation |
| [Provenance](provenance.md) | what every run records, and why |
| [Data provenance](../reference/data-provenance.md) | where the shipped data came from |

## The shape of it, in one picture

```text
   interface          core                     external
   ---------          ----                     --------
   cli.sh    \                                 ld1.x
   ui.sh      >--->  lib/*.sh  ---- exec ---->  oncvpsp.x
   (json)    /         |                        atompaw
                       |                        ... six more
                       v
                   pf_emit  ---> a sink chosen by the interface
```

Three properties hold that together, and each is enforced by a test rather than
by intention:

1. **No module in `lib/` writes to the terminal or reads from stdin.** A
   fourth interface is a rendering problem, not a rewrite.
2. **Engines are declared, not hard-coded.** Everything that enumerates them
   reads the registry, so one cannot be added and left out of the help text,
   the doctor report or the citation list.
3. **Anything that changes the output is recorded where the output lives.**
   Errata, auto-fixes, conversions and proxied functionals all reach
   `PROVENANCE.txt`.

Each of those exists because its absence caused a real bug: a core module that
called `read` and would have hung a web request; a citation list naming four
engines out of nine; an auto-fix that reported itself on the console and
recorded nothing.
