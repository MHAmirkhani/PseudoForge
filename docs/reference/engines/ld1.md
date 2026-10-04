# ld1.x — Quantum ESPRESSO

The atomic code that ships with Quantum ESPRESSO, and the one that produces
PSlibrary. The default engine, and the only one here that generates all three
families.

| | |
|---|---|
| **Families** | NC, US, PAW |
| **Relativity** | non-relativistic, scalar, full |
| **Functionals** | LDA, GGA natively; meta-GGA and hybrids via a [proxy](../../how-to/choose-a-functional.md#meta-gga-and-hybrids-the-proxy-and-one-real-generator) |
| **Native output** | UPF v2, directly |
| **Licence** | GPL-2.0-or-later |
| **Upstream** | <https://gitlab.com/QEF/q-e> |

## Installing

The one engine PseudoForge does **not** build, because it comes with Quantum
ESPRESSO:

```bash
pseudoforge config --set QE_ROOT_DIR=/opt/espresso/7.6
pseudoforge config --set LD1_BIN=/opt/qe/bin/ld1.x     # if it is elsewhere
```

## Input

`ld1.x` reads a Fortran namelist deck. `iswitch=3` generates; `iswitch=2`
tests an existing pseudopotential. PseudoForge writes both.

```bash
pseudoforge recipe Fe -t paw -p psl-high -x pbe
```

```text
 &input
   title='Fe',
   zed=26.,
   rel=1,
   config='[Ar] 4s2 4p0 3d6',
   iswitch=3,
   dft='PBE'
 /
 &inputp
   lpaw=.true.,
   pseudotype=3,
   file_pseudopw='Fe.pbe-spn-kjpaw_psl.1.0.0.UPF',
   ...
 /
6
3S  1  0  2.00  0.00  0.70  1.20  0.0
...
```

The card block is `label n l occupation energy rcut rcutus jj`.

## Parameters PseudoForge maps onto it

| Flag | Namelist variable | Default |
|---|---|---|
| `-x` | `dft` in `&input` | from the profile |
| `-r` | `rel` (0/1/2) | `1`, scalar |
| `--config` | `config` in `&input` | from the recipe |
| `--zed` | `zed` | the element's Z |
| `--zval` | `zval` | computed by the engine |
| `--lloc` | `lloc` in `&inputp` | from the recipe |
| `--rcloc` | `rcloc` | from the recipe |
| `--nlcc` | `nlcc` | from the recipe |
| `--rcore` | `rcore` | from the recipe |
| `--rho0` | `rho0` | unset |
| `--augfun` | `which_augfun` | from the recipe |
| `--rmatch` | `rmatch_augfun` | from the recipe |
| `--beta`, `--tr2` | SCF mixing and threshold | engine defaults |
| `--grid` | `xmin`, `dx`, `rmax` | engine defaults |
| `--rcut-scale` | scales every `rcut`/`rcutus` | 1.0 |
| `--core-hole` | rewrites `config` | none |
| `--gipaw` | `lgipaw_reconstruction` | off |
| `--upf` | UPF v2 only; `--upf 1` is refused (QE 7.x has no v1 writer) | 2 |

Anything not overridden stays exactly as the library's recipe wrote it.

## Idioms worth knowing

**Negative occupations mark unoccupied channels.** `3d-2` in a configuration
means "include d scattering, with no electrons in it". It is not an error and
not minus two electrons.

**`lloc=-1`** builds the local potential from the pseudised all-electron
potential rather than reusing a channel. Often the cure for a ghost state.

**A shell appearing twice** in the card block is two projectors in that
channel — one bound, one at a fixed reference energy. That is what makes a
channel transferable across a range of occupations.

## Transferability

`ld1 iswitch=2` re-solves the atom in configurations from the library's own
test decks and compares eigenvalues against the all-electron answer. This is
the most direct of the transferability measures PseudoForge reports, and it is
graded on the scale in [Validate](../../how-to/validate.md).

PSlibrary ships test decks for its PAW and ultrasoft sets and **not** for
norm-conserving, so a `-t nc` PSlibrary run reports `-` rather than a grade.

## Auto-fix strategies

All of the generic ones apply; see
[Troubleshoot](../../how-to/troubleshoot.md#what-it-classifies-and-what-it-tries).
The classification comes from the routine named in `ld1.x`'s own error banner —
`compute_chi` becomes `chi`, `find_qi` becomes `augmentation`, and so on.

## Known behaviour

**It exits 0 on nonsense.** `ld1.x` will compute a negative valence charge,
write the UPF, and return success. PseudoForge's structural check exists for
this. See [Errata](../errata.md) for a worked case.

**OpenMP.** Some builds spin on all cores waiting for threads they do not use.
PseudoForge sets `OMP_NUM_THREADS=1` for engine processes it launches.

**`upfconv.x` exits 0 on failure** and names its output `.UPF2` rather than
what you asked for. Both are handled and pinned by tests.

## Citation

> P. Giannozzi et al., "QUANTUM ESPRESSO: a modular and open-source software
> project for quantum simulations of materials", *J. Phys.: Condens. Matter*
> **21**, 395502 (2009); and P. Giannozzi et al., "Advanced capabilities for
> materials modelling with Quantum ESPRESSO", *J. Phys.: Condens. Matter*
> **29**, 465901 (2017).
> DOI: [10.1088/0953-8984/21/39/395502](https://doi.org/10.1088/0953-8984/21/39/395502)

If you used a PSlibrary recipe, cite PSlibrary as well —
`pseudoforge citation psl-high`.

---

## On the API

This engine as the server reports it, including whether its binary is
present there:

```bash
curl -s https://pseudo.amirkhani.me/api/engines/ld1
pseudoforge api GET /api/engines/ld1          # the same thing, locally
```

See the [HTTP API reference](../http-api.md). On the public server
`available` is `false` for every engine -- it does not have them, and
[that is the architecture](../../architecture/http.md).

## See also

- [Coverage](../coverage.md) — which elements ld1 covers
- [Limitations](../limitations.md#flags-with-restricted-scope) — where `--projector`, `--rcut-scale` and `--upf 1` apply
- [The native store](../store.md) — the PSlibrary files ld1 produced, shipped with PseudoForge
