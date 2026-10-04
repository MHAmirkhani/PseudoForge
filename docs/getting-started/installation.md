# Installation

PseudoForge is a Bash program. There is nothing to compile and nothing to
install into your system directories — clone it, point it at Quantum ESPRESSO,
and run `doctor`.

The engines are a separate question, and the answer depends on which ones you
need. You do not need all nine to do useful work.

## Requirements

| Needed for | What |
|---|---|
| PseudoForge itself | `bash` 4.2 or newer, `awk`, `sed`, `grep`, `coreutils` |
| Generating anything with `ld1` | Quantum ESPRESSO (`ld1.x`) |
| Building the other engines | `gfortran`, `gcc`, `make` |
| Cutoff convergence scans | Quantum ESPRESSO (`pw.x`) |
| The guided wizard | `whiptail` (Debian: `whiptail`, Fedora: `newt`) |
| Plots | `gnuplot`, **or** `python3` with `matplotlib` |

Everything after the first two rows is optional, and PseudoForge degrades
rather than failing when they are absent. What degrades is listed at the bottom
of this page.

## Install

```bash
git clone https://github.com/MHAmirkhani/pseudoforge.git
cd pseudoforge
./pseudoforge doctor
```

There is no build step. `./install.sh` is available if you want
`pseudoforge` on your `PATH`; it creates a symlink and does not copy anything.

On the first run PseudoForge writes `~/.pseudoforgerc` with commented
defaults. That file is plain shell, sourced at startup, so you can put logic in
it — deriving paths from a module system, for instance.

## Point it at Quantum ESPRESSO

`ld1.x` is the default engine and the only one PseudoForge does not build,
because it ships with Quantum ESPRESSO. Tell PseudoForge where that is:

```bash
pseudoforge config --set QE_ROOT_DIR=/opt/espresso/7.6
```

which is enough if `ld1.x` and `pw.x` are in that directory or its `bin/`. If
they are somewhere else, or named something else, set them individually:

```bash
pseudoforge config --set LD1_BIN=/opt/qe/bin/ld1.x
pseudoforge config --set PW_BIN=/opt/qe/bin/pw.x
```

Any of these can be overridden for a single run by an environment variable:

```bash
LD1_BIN=~/qe-7.4/bin/ld1.x pseudoforge generate -e Si -t paw -p psl-high -x pbe
```

!!! tip "Quantum ESPRESSO with OpenMP"
    On some builds `ld1.x` will spin on all cores waiting for threads it does
    not use. PseudoForge sets `OMP_NUM_THREADS=1` for the engine processes it
    launches. If you run `ld1.x` by hand and it appears to hang, that is why.

## Build the engines

```bash
pseudoforge engines list          # what is present and what is missing
pseudoforge engines build all     # fetch, patch, build, verify
pseudoforge engines build ape     # or one at a time
```

`build all` fetches each engine's source from its upstream, applies the
patches PseudoForge carries where a build needs them, compiles into
`~/.pseudoforge/engines`, and records a build id that goes into the provenance
of anything that engine generates.

It also builds two supporting libraries when an engine needs them:

- **libxc** — the exchange-correlation library. APE needs it; ONCVPSP can be
  linked against it.
- **GSL** — the GNU Scientific Library, which APE needs.

and will fetch `cmake` and `ninja` if the system ones are absent or too old.
Those are fetched on demand rather than required up front, which is why
`doctor` reports them as *optional*.

!!! note "The patches are documented"
    Several engines need changes to build with a modern compiler — legacy
    Fortran assumptions, a stack overflow from a large automatic array. Every
    patch is recorded with what it changes and why, and none of them touches a
    routine, a tolerance or a default. A patch that changed physics would be
    documented as a physics change, not as a build fix.

To see what one engine actually is on your machine:

```bash
pseudoforge engines show atompaw
pseudoforge engines path atompaw     # just the binary
```

If you already have an engine installed elsewhere, point at it instead of
building a second copy:

```bash
pseudoforge config --set ONCVPSP_BIN=/usr/local/bin/oncvpsp.x
```

## Run doctor

```bash
pseudoforge doctor
```

`doctor` checks the toolchain, the engines, the recipe database and the
optional extras, and prints one line per finding with a command that fixes it.
It is also available as `pseudoforge doctor --json` for scripts, and as a panel
in the wizard — the same checks, rendered three ways.

### What doctor reports, and what to do

| Status | Meaning | What to do |
|---|---|---|
| `ok` | present and usable | nothing |
| `missing` | needed, and absent | run the fix command shown |
| `optional` | absent, and that is fine | nothing, unless you want the feature |
| `info` | a fact worth recording | nothing |

Findings you are likely to see on a fresh machine:

**`Quantum ESPRESSO ld1.x — not found`**
: The default engine is unavailable. Set `QE_ROOT_DIR` or `LD1_BIN` as above.
  Without it you can still use the engines PseudoForge builds itself.

**`<engine> — not built`**
: Run `pseudoforge engines build <name>`. Nothing else is affected; the other
  engines and the other profiles work.

**`plotting backend — none`**
: Install `gnuplot`, or `python3` with `matplotlib`. `--plot` says so and exits
  0 without one.

**`mirror — unreachable`**
: Only affects `--source online`. Local generation is unaffected.

## What degrades without the optional pieces

This is the honest list, because "optional" should mean something specific.

| Without | What stops working | What still works |
|---|---|---|
| `whiptail` | the guided wizard | everything on the command line; `pseudoforge` prints the CLI usage instead of starting a wizard it cannot draw |
| `gnuplot` and `matplotlib` | `--plot` draws nothing | the run itself, and the plot *data* is still written to `tests/`, so you can plot it later elsewhere |
| `pw.x` | `--cutoff-scan` | generation and the transferability tests, which use `ld1.x` |
| network access | `--source online`, `engines build` | everything already installed |

No optional component is allowed to turn a successful generation into a
failure. A missing plotting program is not a bad pseudopotential.

## Uninstalling

```bash
rm -rf ~/.pseudoforge          # the engines PseudoForge built
rm -f  ~/.pseudoforgerc        # the configuration
rm -rf /path/to/pseudoforge    # the clone
```

Nothing is installed outside those three places.

---

Next: [Quick start](quickstart.md) makes a pseudopotential, or
[Concepts](concepts.md) explains what the choices mean first.
