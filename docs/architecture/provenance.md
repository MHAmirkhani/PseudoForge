# Provenance

Every run writes `PROVENANCE.txt`. It answers one question: **what, exactly,
made these files?**

Not "PseudoForge made them" — which engine, built from which source, at which
version, with which functional, from which recipe, with what corrected and what
auto-fixed along the way.

!!! note "Two different documents"
    This page is about the provenance of **a run's output**. The provenance of
    the **data PseudoForge ships** — where the recipe database, the element
    table and the functional registry came from — is
    [Data provenance](../reference/data-provenance.md).

## A complete example

```text
# PseudoForge 1.3.2 -- run provenance
# Generated 2026-09-17 00:12:02 +0330

tool.name=PseudoForge
tool.version=1.3.2
engine.id=ld1
engine.label=Quantum ESPRESSO ld1.x
engine.version=v.7.6
engine.build=7de3694ef3fd
engine.binary=/opt/espresso/7.6/ld1.x
engine.upstream=https://gitlab.com/QEF/q-e
profile=psl-high
family=paw
functional=PBE
functional.requested=pbe
relativity=scalar
source=local
autofix.Cu=widen all cut-off radii by 12% and soften the local channel

# element	file	provenance	status
Cu	Cu.pbe-spn-kjpaw_psl.1.0.0-ch1s.UPF	spn.1.0.0	ok
```

## The fields

### Tool and engine

| Field | Why it is there |
|---|---|
| `tool.version` | which PseudoForge |
| `engine.id`, `engine.label` | which code generated |
| `engine.version` | its version, or `unrecorded` — never guessed |
| `engine.build` | **a hash of the built binary** |
| `engine.binary` | where it was |
| `engine.upstream` | where the source came from |

`engine.build` earns its place. Two people with ONCVPSP 4.0.1 can still have
different binaries — different compiler, different libxc, a patch applied — and
when their results differ this is the line that says so.

### What was asked for, and what was used

```text
functional=PBE
functional.requested=pbe
```

These agree when the engine generated what you asked for. They **differ** when
a proxy was used:

```text
functional=PBE
functional.requested=r2scan
```

Two lines rather than one, because the distinction between "this is a PBE
dataset" and "this is a PBE dataset intended for r2SCAN calculations" is
exactly what gets lost when someone inherits a directory of files.

The check is engine-aware: an AtomPAW r2SCAN run records
`functional=R2SCAN` and gets no proxy note, because for AtomPAW the note would
be false.

### Corrections

```text
recipe.erratum=us-low Cs spnl.1.0.0: config corrected from [Xe] 4f14 6s1 6p0 5d0 to [Xe] 4f-1 6s1 6p0 5d0
recipe.erratum.reason=[Xe] is 54 electrons and does not contain 4f, ...
```

A run that used a recipe differing from the library's published one says so,
with the reason. A run that used none says nothing. See
[Errata](../reference/errata.md).

### Auto-fixes

```text
autofix.Cu=widen all cut-off radii by 12% and soften the local channel
```

One line per element that needed one, carrying the note the auto-fix engine
actually wrote. **An auto-fix is a physics change** — a wider radius is a softer
pseudopotential — so it belongs in the durable record and not only in the
console output that scrolled past.

!!! warning "This was broken, and the docs pass found it"
    The provenance used to grep the run record for one phrase the auto-fix
    engine had stopped using. A run that widened copper's radii by 12% reported
    the fix on the console and recorded **nothing** here — in precisely the file
    that is supposed to outlive the console. It now reads the note itself.

### Conversions

A converted file gets its own `<output>.provenance`:

```text
source=Si.van
source_format=van
target_format=upf
tool=upfconv.x
tool_version=7.6
kind=exact
```

`kind` is `exact` or `lossy`. A `lossy` conversion additionally records what
was dropped — the warning is written into the file, not only printed.

### libxc

```text
libxc.version=7.1.2
```

Recorded for engines that link it, because it changes the answer and cannot be
inferred from the build hash alone.

## The other records in a project

`PROVENANCE.txt` is one of four, and they answer different questions:

| File | Question |
|---|---|
| `PROVENANCE.txt` | what made these files |
| `manifest` | the exact settings the project was created with |
| `state.tsv` | per-element status, attempts, timing, message |
| `reports/summary.*` | the human and machine-readable report, in four formats |

`inputs/` holds the exact deck handed to the engine, and `logs/` holds the
engine's unedited output. Between them, a failure is reproducible by hand:

```bash
cd /tmp && ld1.x < ~/out/inputs/Cs.pbe-spnl-rrkjus_psl.1.0.0.in
```

## What is never recorded

**A DOI that has not been minted.** `MD_DOI[pseudoforge]` is empty and stays
empty until one exists.

**A version that could not be determined.** It is written as `unrecorded`, not
guessed.

**A library's name on a file that library did not produce.** Parameters are
labelled `library`, `vendor` or `pseudoforge`, and the distinction survives into
the UPF's author field so it travels with the file.

## For a paper

The recipe file and `PROVENANCE.txt` together are a complete statement of
method: the recipe says what was asked for, the provenance says what actually
ran, down to the engine's build hash.

`pseudos/CITATION.txt` and `pseudos/LICENSE.txt` are written into the same
directory as the pseudopotentials deliberately, so attribution travels with the
files rather than staying with the command that made them.
