# GTH — Goedecker / Teter / Hutter

Analytic pseudopotentials: a dozen coefficients rather than a radial table.
The form CP2K, CPMD and ABINIT read directly.

| | |
|---|---|
| **Families** | NC |
| **Relativity** | scalar; HGH tables carry spin–orbit coefficients |
| **Functionals** | LDA (`pade`), `pbe`, `blyp`, `bp` — as published |
| **Native output** | GTH, CP2K, CPMD, ABINIT variants — **no UPF, and none is possible** |
| **Licence** | GPL-2.0-or-later |
| **Upstream** | <https://github.com/cp2k/cp2k-data> |

## Installing

```bash
pseudoforge engines build gth
```

The binary is `pseudo.x`.

## Why there is no UPF

A GTH pseudopotential *is* its coefficients. There is no radial table to
convert.

> A GTH file is a dozen analytic coefficients, not a radial table. QE's own
> `upfconv.x` lists `.gth` as "DOES NOT WORK". Producing a UPF means sampling
> the analytic form onto a grid, which is a construction rather than a
> conversion.

So `gth → upf` is [**refused**](../formats.md). CP2K, CPMD and ABINIT read GTH
natively; if you need UPF, generate with an engine that writes one.

## Reproducing the published tables

PseudoForge ships the CP2K GTH tables and can emit them in the CP2K, CPMD and
ABINIT layouts. The reproduction is exact: **322 of 322 entries byte-identical**
against the published CP2K tables, which is what the round-trip test asserts.

## Spin–orbit averaging

HGH tables publish j-resolved coefficients. Producing the scalar-relativistic
form means averaging them, using HGH equation (16):

$$ V_l = \frac{l\,V_{l-1/2} + (l+1)\,V_{l+1/2}}{2l+1} $$

PseudoForge implements this rather than dropping one component or taking a
plain mean. Two details matter and are commented in the code: the published
`lpx` must be honoured rather than inferred, and a guard is needed for
channels where the *j* = *l* − ½ component is absent.

## Citation

Every GTH data file carries a **`Please cite:`** block naming three papers, and
all three should be cited for a GGA set:

> S. Goedecker, M. Teter and J. Hutter, "Separable dual-space Gaussian
> pseudopotentials", *Physical Review B* **54**, 1703 (1996).
> DOI: [10.1103/PhysRevB.54.1703](https://doi.org/10.1103/PhysRevB.54.1703)

> C. Hartwigsen, S. Goedecker and J. Hutter, "Relativistic separable dual-space
> Gaussian pseudopotentials from H to Rn", *Physical Review B* **58**, 3641
> (1998).
> DOI: [10.1103/PhysRevB.58.3641](https://doi.org/10.1103/PhysRevB.58.3641)

> M. Krack, "Pseudopotentials for H to Kr optimized for gradient-corrected
> exchange-correlation functionals", *Theoretical Chemistry Accounts* **114**,
> 145 (2005).
> DOI: [10.1007/s00214-005-0655-y](https://doi.org/10.1007/s00214-005-0655-y)

Goedecker/Teter/Hutter for the form, Hartwigsen/Goedecker/Hutter for the
relativistic tables to Rn, and Krack for the gradient-corrected
parametrisations (BLYP, BP, PBE) that most GGA entries come from.

```bash
pseudoforge citation gth
```

prints all three.

---

## On the API

This engine as the server reports it, including whether its binary is
present there:

```bash
curl -s https://pseudo.amirkhani.me/api/engines/gth
pseudoforge api GET /api/engines/gth          # the same thing, locally
```

See the [HTTP API reference](../http-api.md). On the public server
`available` is `false` for every engine -- it does not have them, and
[that is the architecture](../../architecture/http.md).

## See also

- [Coverage](../coverage.md) — which elements GTH covers
- [Limitations](../limitations.md#conversions-that-do-not-exist) — why `gth → upf` is refused on physics, not on tooling
- [The native store](../store.md) — the GTH, CP2K, CPMD and ABINIT files shipped with PseudoForge
