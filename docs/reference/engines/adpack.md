# ADPACK — Ozaki

Taisuke Ozaki's generator for OpenMX. Troullier–Martins, Bachelet–Hamann–
Schlüter and MBK schemes.

| | |
|---|---|
| **Families** | NC |
| **Relativity** | as the shipped deck specifies — **not retargetable**, see below |
| **Functionals** | PZ LDA and PBE GGA; other native functionals are refused |
| **Native output** | OpenMX `.vps` and `.pao` — **no UPF** |
| **Licence** | GPL-2.0-or-later |
| **Upstream** | <http://www.openmx-square.org/adpack/adpack.html> |

## Installing

ADPACK is built from source like the other engines (`pseudoforge engines build adpack`). Released ADPACK source carries hardcoded paths to author-specific include and library paths in `source/makefile`; PseudoForge patches the makefile to use standard compiler flags and system BLAS/LAPACK (`-lblas -llapack`) before compiling.

The build applies a versioned ADPACK 2.2 source patch with `patch` and
recompiles every object, including objects included in the archive. The patch
fixes the native radial-grid and SCF limit checks, returns a failure status on
invalid parsed inputs, and declares the LAPACK `dstevx_` routine for modern
C compilers. The bundled defaults and pseudization equations stay as upstream
defines them.

```bash
pseudoforge engines build adpack
```

Alternatively, if you already have it compiled elsewhere, set `ADPACK_BIN` in `~/.pseudoforgerc`:

```bash
# Set in ~/.pseudoforgerc:
ADPACK_BIN="/path/to/adpack"
```

## Coverage: 29 bundled elements and supplied native inputs

PseudoForge ships the 29 per-element decks the distribution provides under
`work/` — the author's radii, reference configurations and schemes,
unchanged unless the user requests controls or a recorded automatic correction.
Use `physics adpack` for mapped channel/local radii, NLCC, grid, SCF, native
construction/projector settings and ghost search. Complete edited inputs are
accepted through [the manual workflow](../../how-to/manual-generation.md).

**There is no synthesised fallback for other elements.** An ADPACK deck fixes
the scheme, the local channel and per-channel radii that were chosen by hand.
For another element, provide a complete native input with `--params`; its
nuclear charge and coupled solver blocks must match the request.

## No UPF, and no conversion to one

`.vps` holds semilocal potentials $V_l(r)$, one curve per channel. UPF wants a
separable Kleinman–Bylander form: projector functions and a $D_{ij}$ matrix.
Going from one to the other means choosing a local channel and constructing
projectors — a new pseudopotential, not a relabelled file.

So `vps → upf` is [**refused**](../formats.md). Use ADPACK's output with
OpenMX, which reads it natively. The repository's
`examples/engine-pairs/evaluate_openmx.py` exercises the real reader on three
generated He VPS files and records SCF convergence separately from file loading.

## The build fix

Released ADPACK 2.2 allocates about 9 MB of radial work arrays on the stack in
`MBK()` — `Chi[2][15][20000]` alone is 4.8 MB — and segfaults partway through
every element on a default 8 MB stack limit. The measured frame was 9,048,480
bytes.

PseudoForge builds from a patched tree that moves those arrays to the heap,
using pointer-to-array types so every existing `beta[i][j]` and `Chi[i][j][k]`
reference is untouched. The frame drops below 100 KB.

**This changes no physics.** No routine, tolerance, default or input deck is
modified, and a test asserts that no decimal number appears in the patch.

You can confirm the diagnosis without applying anything:

```bash
ulimit -s unlimited      # the unpatched build then runs to completion
```

## Relativity cannot be retargeted

`eq.type` is coupled to the shape of other blocks in the same deck. With
`dirac`, the `<log.deri.R>` table carries two values per channel — one for each
*j* = *l* ± ½. Rewriting the keyword alone leaves that table the wrong shape,
and ADPACK stops with `Format error for log.deri.R`, pointing at a block nobody
touched.

The adapter therefore does not retarget the solver keyword alone. To use a
different solver, edit all coupled blocks in the prepared input and import it
with a matching `-r` choice. A supplied-input mismatch is refused. `xc.type`
can be retargeted between native PZ and PBE; PW LDA and PBEsol are not aliases
for these functionals.

## Tellurium

ADPACK's Troullier–Martins root-finder cannot find a coefficient `c2` for the
radii shipped in `Te_VPS.inp`. It declines cleanly — exit 0, no file, and a
message naming the step.

The auto-fix engine retries with scaled radii:

| Failure | Attempt 1 | Attempt 2 |
|---|---|---|
| TM root-finder cannot find `c2` | rc × 1.1 | rc × 1.2 |

The shipped deck is **never modified**: the retry edits a copy in the scratch
directory, and `data/params/adpack/Te_VPS.inp` stays byte-identical to the
distribution, which a test asserts. The scale that succeeded is recorded as
`autofix.rc_scale` in `PROVENANCE.txt` and carried in the report, because a
wider radius is a softer pseudopotential — a real change to the physics, not a
build fix.

`--no-autofix` disables this retry. If a retry succeeds, project inputs retain
both the requested and successful versions and their checksums. A native
bound-ghost detection rejects the output even with optional testing disabled;
a nonconverged ghost search warns that absence of ghosts is not established.

!!! note "Why a retry and not a rule"
    28 of the 29 elements build with the published radii and never reach the
    retry. A blanket "scale ADPACK radii by 1.1" rule would have changed 28
    answers to fix one.

## Validator

`.vps` validation was got wrong twice while being written, both times by
inventing a keyword rather than reading a real file:

- a check for a `Vps.public` keyword that does not exist in the format, which
  rejected every file ADPACK produces;
- the banner of asterisks a `.vps` opens with, flagged as a Fortran overflow
  marker.

Both were caught by fixture tests. The rule that came out of it —
**read a real output file before writing the check** — is in
[Adding an engine](../../contributing/adding-an-engine.md).

## Citation

> T. Ozaki, "Variationally optimized atomic orbitals for large-scale
> electronic structures", *Physical Review B* **67**, 155108 (2003).
> DOI [10.1103/PhysRevB.67.155108](https://doi.org/10.1103/PhysRevB.67.155108)
>
> T. Ozaki and H. Kino, "Numerical atomic basis orbitals from H to Kr",
> *Physical Review B* **69**, 195113 (2004).
> DOI [10.1103/PhysRevB.69.195113](https://doi.org/10.1103/PhysRevB.69.195113)

**ADPACK's author asks for no citation** — recorded as `no-request`. Checked
2026-09-27:

| where | what it says |
|---|---|
| the tarball | `source/`, `work/`, `work_FEMHF/`, `work_FEMLDA/`; no `README`, no `doc/`. Each source file carries `Copyright (C) 2002-2007, Taisuke Ozaki` and a GPL notice |
| the [ADPACK 2.2 user's manual](https://www.openmx-square.org/adpack_man2.2/), 2011-09-28, read in full | no request anywhere, including §14 *Others* and the licence |

The two papers above are the manual's own reference [15], which it gives for
ADPACK's own contribution: *generation of pseudo-atomic orbitals under a
confinement potential*. Everything else ADPACK implements — Troullier–Martins,
BHS, MBK, Kleinman–Bylander — is someone else's method, and the manual cites
those separately; cite the one your deck used.

The URL that used to be recorded for ADPACK,
`openmx-square.org/adpack/adpack.html`, now returns 404.

---

## On the API

This engine as the server reports it, including whether its binary is
present there:

```bash
curl -s https://pseudo.amirkhani.me/api/engines/adpack
pseudoforge api GET /api/engines/adpack          # the same thing, locally
```

See the [HTTP API reference](../http-api.md). On the public server
`available` is `false` for every engine -- it does not have them, and
[that is the architecture](../../architecture/http.md).

## See also

- [Coverage](../coverage.md) — which elements ADPACK's 29 decks cover
- [Limitations](../limitations.md#adpack-29-elements-full-relativistic-only) — the 29-element set and the Te refusal
- [The native store](../store.md) — the ADPACK files shipped with PseudoForge
