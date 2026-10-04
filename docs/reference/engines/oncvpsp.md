# ONCVPSP — Hamann

Hamann's optimised norm-conserving Vanderbilt construction. Norm-conserving
pseudopotentials that are unusually soft for the family, which is why SG15 and
PseudoDojo are built with it.

| | |
|---|---|
| **Families** | NC |
| **Relativity** | scalar, full (j-dependent) |
| **Functionals** | a small built-in set; a much wider range when built against libxc |
| **Native output** | UPF, psp8, xml (QE), directly |
| **Licence** | GPL-3.0 |
| **Upstream** | <https://github.com/oncvpsp/oncvpsp> |

## Installing

```bash
pseudoforge engines build oncvpsp
pseudoforge engines show oncvpsp     # version, build id, libxc or not
```

PseudoForge builds libxc first when it is not already present, and links
against it.

## Use it for

- Anything downstream that requires norm-conserving: GW, BSE, TDDFT, EPW.
- Heavy elements, where the alternative norm-conserving constructions are very
  hard.
- Reproducing SG15 or PseudoDojo, which are its own published tables.

```bash
pseudoforge generate -e Au -t nc -p sg15 -x pbe -r full --engine oncvpsp -o ./out
```

## Input

ONCVPSP's own format, not a Fortran namelist:

```text
# ATOM AND REFERENCE CONFIGURATION
# atsym, z, nc, nv, iexc   psfile
    Au   79    10   4   4   upf
#
# n, l, f  (nc+nv lines)
1 0 2
2 0 2
...
```

`nc` and `nv` are the core and valence shell counts. `iexc` selects the
functional.

## The functional encoding

ONCVPSP's built-in functionals are small positive integers. Anything outside
that set uses its libxc encoding:

$$ \texttt{iexc} = -(1000 X + C) $$

where X and C are the libxc exchange and correlation identifiers. PseudoForge
writes this automatically — but it only works if **your** ONCVPSP was built
against libxc.

!!! warning "A stub-linked build silently gives you PBE"
    If ONCVPSP was built without libxc and you ask for a functional outside its
    built-in set, the result is not what you asked for. PseudoForge warns when
    this can happen; `pseudoforge engines show oncvpsp` reports whether libxc
    is linked.

    This warning existed but was never called for a while — the function was
    defined and nothing invoked it, so a PBEsol request against a stub build
    produced PBE with nothing said. Found in a call-graph audit and fixed.

## Meta-GGA

**ONCVPSP has no meta-GGA code path.** Linking libxc does not add one — libxc
supplies the functional, but the generator has no place to use the
kinetic-energy density. Asking for SCAN or r2SCAN produces a PBE dataset with
the proxy note. For a real meta-GGA dataset, see
[AtomPAW](atompaw.md).

## Parameters

| Flag | Effect |
|---|---|
| `-r full` | j-dependent projectors, roughly doubling the projector count |
| `--rcut-scale` | scales the per-channel radii in the deck |
| `--format upf,psp8` | any combination it writes natively |

## Transferability

ONCVPSP runs its own configuration tests and PseudoForge reports them under
`oncvpsp's own test configurations`. These are **not** on the same scale as
`ld1 iswitch=2`, and the method is printed alongside the result so the two are
never silently compared.

It also reports ghost states. A positive-energy ghost far above the valence
region — tens of Ry — is labelled informational rather than treated as a
failure; those are common in published norm-conserving tables including SG15's
own files. A ghost near or below the valence energies is a real problem. See
[Tutorial 5](../../tutorials/05-gold.md#the-warning).

## Citation

> D. R. Hamann, "Optimized norm-conserving Vanderbilt pseudopotentials",
> *Physical Review B* **88**, 085117 (2013); erratum *Physical Review B*
> **95**, 239906(E) (2017).
> DOI: [10.1103/PhysRevB.88.085117](https://doi.org/10.1103/PhysRevB.88.085117)

Cite SG15 or PseudoDojo separately if you used their tables —
`pseudoforge citation sg15`.

---

## On the API

This engine as the server reports it, including whether its binary is
present there:

```bash
curl -s https://pseudo.amirkhani.me/api/engines/oncvpsp
pseudoforge api GET /api/engines/oncvpsp          # the same thing, locally
```

See the [HTTP API reference](../http-api.md). On the public server
`available` is `false` for every engine -- it does not have them, and
[that is the architecture](../../architecture/http.md).

## See also

- [Coverage](../coverage.md) — which elements ONCVPSP covers
- [Limitations](../limitations.md#psml) — why PSML is not in the format registry
- [The native store](../store.md) — the ONCVPSP psp8 and UPF files shipped with PseudoForge
