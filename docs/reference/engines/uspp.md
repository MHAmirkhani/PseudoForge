# USPP — Vanderbilt

Vanderbilt's original ultrasoft code. Use it to reproduce the classic
Vanderbilt tables or older work generated with it; for new ultrasoft work,
[`ld1`](ld1.md) is usually the more convenient route.

| | |
|---|---|
| **Families** | US |
| **Relativity** | scalar |
| **Functionals** | LDA, GGA |
| **Native output** | `.van` / `.uspp` — **no UPF**, but the conversion is exact |
| **Licence** | GPL-2.0-or-later |
| **Upstream** | <https://www.physics.rutgers.edu/~dhv/uspp/> |

## Installing

```bash
pseudoforge engines build uspp
```

The binary is `runatom.x`.

## Getting to UPF

`van → upf` is an **exact** conversion, performed by Quantum ESPRESSO's own
`upfconv.x`. Every number survives, and the conversion is recorded in the
provenance:

```text
source_format=van
target_format=upf
tool=upfconv.x
kind=exact
```

There is an extra step in the pipeline — `runatom.x` writes a `.uspp` that is
reformatted before conversion — and PseudoForge handles it. Nothing about it
changes the physics.

## Parameters

PseudoForge uses USPP's own vendor database: `Work/<NNN>-<El>/`, Vanderbilt's
per-element decks. Files generated from it are labelled `vendor` in the
provenance.

## Remember the dual

Ultrasoft needs `ecutrho` around **8×** `ecutwfc`, not the 4× that suits
norm-conserving. The augmentation charge is sharp even when the wavefunction is
smooth, and getting this wrong is one of the most common sources of
irreproducible ultrasoft results.

```bash
pseudoforge generate -e Si -t us --engine uspp --cutoff-scan -o ./out
```

measures both rather than assuming.

## Citation

> D. Vanderbilt, "Soft self-consistent pseudopotentials in a generalized
> eigenvalue formalism", *Physical Review B* **41**, 7892(R) (1990).
> DOI: [10.1103/PhysRevB.41.7892](https://doi.org/10.1103/PhysRevB.41.7892)

---

## On the API

This engine as the server reports it, including whether its binary is
present there:

```bash
curl -s https://pseudo.amirkhani.me/api/engines/uspp
pseudoforge api GET /api/engines/uspp          # the same thing, locally
```

See the [HTTP API reference](../http-api.md). On the public server
`available` is `false` for every engine -- it does not have them, and
[that is the architecture](../../architecture/http.md).

## See also

- [Coverage](../coverage.md) — which elements USPP covers
- [Limitations](../limitations.md#conversions-that-do-not-exist) — why the USPP-to-UPF path is not a conversion but a rewrite
- [The native store](../store.md) — the `.van` and `.uspp` files shipped with PseudoForge
