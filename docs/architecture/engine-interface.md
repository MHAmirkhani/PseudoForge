# The engine interface

Nine engines, one driver. This is the contract between them.

For the step-by-step of adding a tenth, see [Adding an
engine](../contributing/adding-an-engine.md).

## The registry

Every engine declares itself in `lib/engines.sh`:

```bash
ENG_LABEL[oncvpsp]="ONCVPSP (Hamann)"
ENG_FAMILIES[oncvpsp]="nc"
ENG_BIN_VAR[oncvpsp]=ONCVPSP_BIN
ENG_BINARIES[oncvpsp]="oncvpsp.x"
ENG_SRC[oncvpsp]="..."
ENG_UPSTREAM[oncvpsp]="https://github.com/oncvpsp/oncvpsp"
ENG_LICENSE[oncvpsp]="GPL-3.0"
ENG_NATIVE_UPF[oncvpsp]=yes
ENG_NOTE[oncvpsp]="..."
```

The registry is **the list**. Everything that enumerates engines — the help
text, the doctor report, the citation list, the generated
[engines reference page](../reference/engines.md) — reads it through
`eng_list`, so a tenth engine cannot be added and left out of one of them.

!!! note "It could, and was"
    Both the `--engine` help text and `cmd_citation` carried hand-written
    lists of four engines while nine existed. The citation one mattered: a user
    publishing work made with APE or ADPACK would never have been told to cite
    them. Both now read the registry.

## What an engine must provide

| Capability | Function | Answers |
|---|---|---|
| families | `ENG_FAMILIES` | nc, us, paw — which can it make? |
| functionals | `ib_<engine>_xc` | can it generate this functional itself? |
| relativity | the deck builder | which solvers does it have? |
| native format | `ENG_NATIVE_UPF`, `data/formats.tsv` | what does it write? |
| deck construction | `ib_build_<engine>` | turn a `SPEC` into its input |
| execution | `exec_<engine>` | run it, in an isolated directory |
| validation | a validator | did it produce something usable? |

## Capability queries answer before anything runs

```bash
eng_exists oncvpsp
eng_supports_family oncvpsp us       # false
eng_available oncvpsp                # is the binary actually there?
eng_resolve oncvpsp                  # where
```

A request an engine cannot honour is refused **before** anything is written:

```text
ERROR ONCVPSP (Hamann) cannot make us pseudopotentials (it does: nc)
ERROR ONCVPSP (Hamann) cannot write 'recpot' (it writes: upf psp8 xml)
ERROR AtomPAW cannot generate meta-GGA with a relativistic solver.
```

Nothing half-written, and the message names the constraint rather than
producing a Fortran traceback forty elements in.

## The functional question is asked of the engine

`XC_STATUS` marks meta-GGA as a proxy, and for eight engines that is right.
AtomPAW is the exception, and a proxy that ignored the engine would hand an
AtomPAW user a PBE dataset while their input said r2SCAN.

So the engine's own functional mapper is the authority:

```bash
xc_engine_native() {
    local id=$1 eng=${2:-${SPEC[engine]:-ld1}}
    case $eng in
        atompaw) ... ib_atompaw_xc ... ;;
        *) return 1 ;;
    esac
}
```

It calls the same function that builds the deck, rather than consulting a
second table that could disagree with it.

## Execution is isolated

```bash
work=$SCRATCH_DIR/$$-$el
```

Per-process **and** per-element. `ld1.x` writes `ld1.wfc` and `vx.pot` by fixed
name into its working directory; two workers sharing one would overwrite each
other's intermediates and produce results that depend on the race, silently.

The directory is removed afterwards unless `PF_KEEP_SCRATCH=1`.

## Parameters have a provenance

Owning the engine is not owning the parameters. What makes SG15 "SG15" is its
published table of radii and projector counts, not the fact that ONCVPSP
consumed them.

| provenance | meaning |
|---|---|
| `library` | the library's own published inputs, supplied via `--params` |
| `vendor` | inputs shipped inside the engine's own source tree |
| `pseudoforge` | PseudoForge's own construction from the ground state plus a documented radius heuristic |

The distinction is in `state.tsv`, in every report, and in the UPF's author
field, so it survives the file being copied elsewhere. PseudoForge will run
ONCVPSP for you; it will not invent SG15's table and then put SG15's name on the
result.

## Build fixes may not change physics

Several engines need patches to build with a modern compiler. The rule:

!!! abstract "No routine, tolerance, default or input deck may be modified by a build fix."

ADPACK's patch moves 9 MB of radial arrays off the stack, using
pointer-to-array types so every existing subscript is untouched. A test asserts
**no decimal number appears in the patch**.

A patch that did change physics would be documented as a physics change, not as
a build fix.

## Auto-fix strategies are per-failure, not per-engine

The auto-fix engine classifies from the engine's own error and retries. Each
strategy fires only on a specific signature, so an element whose first attempt
succeeds never reaches one.

That is deliberate. Bromine's 3d¹⁰ is deep semicore and treating it as core is
the textbook choice for a halogen — but **zinc has the same 3d¹⁰/4s² shape and
builds correctly with its d pseudised**. A blanket rule would have changed
zinc's answer to fix bromine. A retry does not.

The full table is in
[Troubleshoot](../how-to/troubleshoot.md#what-it-classifies-and-what-it-tries).
