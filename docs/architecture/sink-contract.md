# The sink contract

One rule, and everything else on this page follows from it:

!!! abstract "No module in `lib/` may write to the terminal."

A core module that calls `echo`, writes to stderr, or reads from stdin has
decided that a human is watching. That decision belongs to the interface, and a
module that makes it cannot be used by a JSON endpoint, a web service, or a
wizard that is mid-draw on a whiptail screen.

## The three channels

Everything a core function produces goes down exactly one of three:

**Data → stdout**
: The thing the caller asked for. A path, a deck, a list. Nothing else is ever
  on stdout, so `$(...)` around a core function returns the value and not a
  progress message.

**Status → exit code**
: Whether it worked. `0` or non-zero. Never a string a caller has to match.

**Messages → `pf_emit`**
: Everything a human might want to read, tagged with a level. Never printed
  directly.

```bash
info()   { pf_emit info   "$@"; }
ok()     { pf_emit ok     "$@"; }
warn()   { pf_emit warn   "$@"; }
error()  { pf_emit error  "$@"; }
debug()  { pf_emit debug  "$@"; return 0; }
banner() { pf_emit banner "$@"; }
die()    { error "$@"; exit 1; }
```

Those six verbs are the whole interface between the core and whatever is
watching.

## `pf_emit`

```bash
PF_SINK=${PF_SINK:-pf_sink_cli}

pf_emit() {
    local level=$1; shift
    local message; printf -v message '%s' "$*"
    if [ -n "${PF_LOGFILE:-}" ]; then ... fi
    "$PF_SINK" "$level" "$message"
}
```

One choke point. Changing where messages go is changing one variable.

## The sinks

| Sink | Renders as |
|---|---|
| `pf_sink_cli` | coloured, level-prefixed lines on the terminal |
| `pf_sink_capture` | accumulated into `PF_SINK_RECORDS` for later inspection |
| `pf_sink_json` | one JSON object per line, streaming |
| `pf_sink_null` | discarded |

```bash
pf_sink_use capture    # cli | capture | json | null
pf_sink_reset
some_core_function
pf_sink_count error    # how many things went wrong
pf_sink_filter error   # what they were
pf_sink_use cli
```

The wizard uses `capture` around anything that runs while a whiptail screen is
up, because a core module printing mid-draw would scribble over the dialog.

### JSON is line-delimited on purpose

One object per line rather than one array, so a long operation streams instead
of buffering, and a truncated response is still parseable up to the cut.

## Asking the user

A core module must not call `read`. It would hang a web request forever and
there would be no way to find out why.

```bash
pf_confirm "overwrite the existing recipe?" || return 0
```

| Implementation | Behaviour |
|---|---|
| `pf_confirm_tty` | prompts, when stdin is a terminal |
| `pf_confirm_assume` | answers from a policy, without asking |

The interface installs one. The core asks the question and does not care who
answers.

!!! note "This was a real bug, twice"
    `build.sh:124` and `executor.sh:581` called `read` directly. Both would
    have hung a web API with no diagnosis. Found in a call-graph audit and
    replaced with `pf_confirm`.

## Findings are not messages

A check that discovers something produces a **record**, not a warning:

```text
<category>\t<name>\t<status>\t<detail>\t<fix>
```

`doctor_checks` emits nothing through the sink at all — a test asserts the
count is zero — and returns records. Three renderers turn them into a CLI
report, a JSON stream and a TUI panel.

Whether a missing engine deserves a yellow line is the interface's decision,
and interfaces disagree: the wizard shows it as a panel row with a Fix button,
the CLI prints it with a command, the JSON endpoint just carries the status.

## What a core module may not do

| Not this | This |
|---|---|
| `echo "generating $el"` | `info "generating $el"` |
| `echo "failed" >&2` | `error "failed"` |
| `read -r answer` | `pf_confirm "..."` |
| `exit 1` deep in a helper | `return 1`, and let the caller decide |
| `tput`, `clear`, ANSI escapes | the sink adds colour, if the interface wants it |
| `printf` a progress bar | `pf_emit_stream`, or let the interface draw one |

`tests/test_interfaces.sh` enforces the first three by inspection, so a
regression fails the suite rather than being discovered by whoever builds the
next interface.

## Why a sink rather than threaded return values

The alternative is for every function to return its messages to its caller,
which returns them to its caller, up to the interface.

That means changing the signature of every function in 31 modules, and it means
every intermediate caller has to decide what to do with messages it does not
understand. The cost falls on 29 modules that do not care, to serve a boundary
that exists in one place.

A sink puts the cost where the decision is.

## Adding a fourth interface

Write a sink, install it, call the same functions:

```bash
pf_sink_use json
pf_config_load
cmd_generate
```

A web service is a rendering problem, not a rewrite. That is the whole point of
the rule at the top of this page.

See [Overview](overview.md) for how this fits with the rest.
