# OPIUM — Rappe group

The Rappe group's optimised norm-conserving generator. Notable here for the
sheer number of output formats it writes from one generation.

| | |
|---|---|
| **Families** | NC |
| **Relativity** | scalar |
| **Functionals** | LDA, GGA |
| **Native output** | UPF for every case; FHI, CASTEP recpot, SIESTA psf, CPMD, CASINO, CHAMP, QSO, NCPP for scalar/non-relativistic runs; Teter for fully-relativistic runs |
| **Licence** | GPL-2.0 |
| **Upstream** | <https://github.com/rappegroup/opium> |

## Installing

```bash
pseudoforge engines build opium
```

## Use it for

Getting the same pseudopotential into several codes without a conversion step:

```bash
pseudoforge generate -e Si -t nc --engine opium --format upf,fhi,siesta,cpmd -o ./out
```

Each is written by OPIUM itself, so none of them is a conversion and none
carries a conversion's caveats. A format the engine cannot write is refused
before anything runs.

### Format availability by relativity

OPIUM 4.1.0 itself restricts which formats can be written for each
relativity mode, and the restriction lives in its writers, not here:

| Mode | Formats OPIUM writes |
|---|---|
| scalar / non-relativistic | UPF, FHI, recpot, SIESTA, CPMD, CASINO, CHAMP, QSO, NCPP |
| fully relativistic | UPF, Teter |

`teter` refuses anything but a fully-relativistic potential; the other
eight formats refuse a fully-relativistic potential. PseudoForge drops the
formats the chosen mode cannot produce rather than ask OPIUM to write a
file it will then refuse to write.

### Upstream bug: six writers crash on d-shell elements

Six of the ten writers (FHI, NCPP, CPMD, CASINO, CHAMP, SIESTA) build the
`<name>.pot.ps.l=N` scratch-file names from the loop index instead of the
real angular momentum, so on any element whose valence l-shells are not
contiguous -- 3d and 5d metals -- they asked `fopen` for a file that was
never written, and `fread(NULL, ...)` segfaulted.

PseudoForge applies a local patch to the OPIUM source tree between
`build_prepare_src` and `configure`/`make` (see
[`lib/patches/opium/README.md`](https://github.com/MHAmirkhani/pseudoforge/blob/main/lib/patches/opium/README.md) for the exact patch and
the reasoning behind it). The upstream tree is untouched on disk; the fix
is applied to the working copy only, at build time, idempotently.

The bug is upstream and the fix is reported:

- [rappegroup/opium#1](https://github.com/rappegroup/opium/issues/1) — the issue
- [rappegroup/opium#2](https://github.com/rappegroup/opium/pull/2) — the pull request

When the patch is merged upstream the local one becomes a no-op: the apply
script detects the corrected form and skips those files.

Verified on Fe, Cu, Zn, Au (all ten formats now write), and on Si, Na, Mg,
Al, Cl, Ca, Ga (unchanged).

## Transferability

OPIUM reports its own design diagnostics, and PseudoForge reports them under
that name. They are **not** on the same scale as `ld1 iswitch=2` — the method
is printed with the result so the two are never silently compared.

## Validator note

OPIUM's design-diagnostic output prints values in mRy **and** meV on the same
line. An early version of the parser took the first float it found, which is a
13.6× error. It now takes column 4 specifically.

This is the kind of thing that only shows up if you read a real output file
rather than imagining its shape. See
[Adding an engine](../../contributing/adding-an-engine.md).

## Citation

> A. M. Rappe, K. M. Rabe, E. Kaxiras and J. D. Joannopoulos, "Optimized
> pseudopotentials", *Physical Review B* **41**, 1227 (1990).
> DOI [10.1103/PhysRevB.41.1227](https://doi.org/10.1103/PhysRevB.41.1227)

**OPIUM's authors ask for no citation, and there is no paper for the software
itself** — recorded as `no-request`. Checked 2026-09-27: `opium-4.1.0`'s
`README`, `INSTALL`, `COPYING` and `doc/{README,README_fortran,README_solidstatecodes,CHANGELOG}`,
the [project site](https://opium.sourceforge.net/), and its
[scientific references](https://opium.sourceforge.net/sci.html) page, which
lists the methods OPIUM implements without asking for any of them.

The paper above is that page's reference [2], for the **optimized** scheme —
and PseudoForge's OPIUM decks select exactly that, `opt`, in their `[Pseudo]`
section. **If you change a deck to `kerker` or `tm`, this is no longer the
right reference**: the same page lists Kerker (1980) and the others, and the
one to cite is the one matching the construction you ran.

---

## On the API

This engine as the server reports it, including whether its binary is
present there:

```bash
curl -s https://pseudo.amirkhani.me/api/engines/opium
pseudoforge api GET /api/engines/opium          # the same thing, locally
```

See the [HTTP API reference](../http-api.md). On the public server
`available` is `false` for every engine -- it does not have them, and
[that is the architecture](../../architecture/http.md).

## See also

- [Coverage](../coverage.md) — which elements OPIUM covers
- [Limitations](../limitations.md#opium-d-shell-writers-crash-upstream) — the d-shell writers, and what the local patch does
- [Upstream](../upstream.md#opium-six-writers-crash-on-d-shell-elements) — the issue, the pull request, and how to tell if the patch is still needed
- [The native store](../store.md) — the OPIUM files shipped with PseudoForge
