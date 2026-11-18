# Prepare, edit and generate with any engine

All nine adapters can prepare complete native inputs, adopt them with
`--params`, and execute from a separate project. This is the expert path for
reference configurations, semicore partitions, occupations, projector bases,
and coupled settings that cannot be expressed by a single common flag.

## One workflow

```bash
pseudoforge physics atompaw
pseudoforge prepare -e Si -t paw -p atompaw --engine atompaw -x pbe \
  --rcut-scale 1.02 --engine-option paw.shape=Besselshape -o ./si-inputs
# Edit the files under ./si-inputs/inputs, then:
pseudoforge generate -e Si -t paw -p atompaw --engine atompaw -x pbe \
  --params ./si-inputs/inputs --no-autofix -o ./si-result
cd si-result
sha256sum -c inputs.sha256
```

`prepare` requires a new or empty directory and runs no atomic generator.
Its inputs already include requested overrides. Its printed follow-up command
clears those overrides, adopts the snapshot, and disables automatic physics
changes. Repeating a global scale on the imported input would scale it again.
Source and output input directories must not overlap. Ordinary generation also
writes `inputs.sha256` for retained native files. Successful APE/ADPACK retries
retain both requested and executed input versions, so both are hashed.

The terminal advanced menu offers **Prepare / edit complete native inputs**,
**Use an existing native-input directory**, and **Native physics controls and
units**. The editor comes from `VISUAL` or `EDITOR` (default `vi`); editor text
is not evaluated as a shell program. The web Customize page exposes typed
controls and produces both preparation and import commands. Files stay on your
computer; the public API does not execute generators.

The common XC and relativity choices remain part of the specification. Native
headers must agree with them: adapters retarget supported standalone fields or
refuse mismatches. For example, changing ADPACK's solver also requires changing
its coupled logarithmic-derivative table. A supplied input can use a physical
mode different from a library's published default, provided the adapter and
native input actually support it. Merely renaming the output is insufficient.

## Native files and physical choices

`El` means the selected element. The names below are emitted by preparation;
legacy element-named library inputs remain accepted where previously supported.

| Engine | Editable files | Important native physics |
| --- | --- | --- |
| ld1 | `El.*.in` (or `El.in`) | Reference configuration, frozen core/semicore, charge, occupations, NC/US/PAW construction, augmentation, local potential and wavefunction/projector cards |
| ONCVPSP | `El.dat` | Core/valence counts and matching state list; channel radii/reference energies; continuity and optimization basis; kinetic optimization; projector number/separation; local potential; model core charge; unfitted test configurations |
| USPP | `El.ae.adat`, `El.ps.adat` | Paired AE/PS occupations and state counts, beta projectors, local potential, partial core and augmentation-charge radii, SCF and construction settings |
| fhi98PP | `El.ini`, `El.fort20` | Core/valence partition, orbital occupations, XC code, pseudocore radius, TM/Hamann construction, optional channel radii/energies, scalar/nonrel solver and explicit spin occupations |
| OPIUM | `el.param` | `[Atom]` states, `[Pseudo]` valence radii/method, `[Optinfo]`, native local/core sections, XC/relativity and independent `[Configs]` |
| GTH fit | `El.gth-inputs/atom/atom.dat`, `psp_XC/{psp.par,FITPAR,weights.par}` | Atomic references/confinement/grid, analytic Gaussian parameters, which parameters may vary, and fitting weights |
| GTH coefficients | `El.gth-source` (or `El.gth`) | Direct analytic coefficient input; copying this file performs no fitting |
| AtomPAW | `El.atompaw.input` | Reference states and c/v markers, PAW/shape/local radii, additional projector states/energies, pseudization and compensation-charge shape |
| APE | `El.inp.ape` | Explicit orbital/core blocks and XC pair, wave equation, component radii/method, local channel, core correction, and numerical tolerances |
| ADPACK | `El.adpack.inp` (or `El_VPS.inp`) | Occupation and valence counts, solver and coupled tables, radial grid, SCF, pseudization channels, local potential, projectors, partial core and ghost search |

USPP uses **fixed-width Fortran records**: integers occupy five columns and many
radii ten columns. Preserve those widths when editing state counts or complete
records. Typed controls preserve them automatically. Counts and their dependent
tables must agree in every generator; changing `nval` or `lmax` alone is unsafe.
In AtomPAW the c/v markers, extra-state prompts and matching-radius counts are
coupled. The typed radius adapter checks the prepared VANDERBILT layout; other
native constructions can be edited in the complete input instead.

## Shared controls, native meanings

`pseudoforge physics ENGINE` is the live catalogue. Native `KEY=VALUE` settings
are repeated with `--engine-option`; unknown, duplicate, nonfinite and out-of-range
values are refused. Their schema and units come from `data/physics-controls.tsv`
and are also returned by `GET /api/engines`. A requested channel must exist.
Native-energy/tolerance conventions are explicitly labelled; those numbers are
not treated as a common cross-engine accuracy measure.

| Engine | Mapped controls beyond the complete native input |
| --- | --- |
| ld1 | Existing reference/charge/core-hole, radii, NLCC, augmentation, grid, SCF and projector controls |
| ONCVPSP | Matching radii, local radius/channel, NLCC; per-channel `qcut`, `ncon`, `nbas`, `nproj`, `debl`, and `dvloc0` |
| USPP | Matching/local/partial-core radii, NLCC, global radius scaling; `rinner`, `thresh`, `tol`, `damp` (SCF settings apply to both stages) |
| fhi98PP | Explicit channel radii, pseudocore/NLCC, spin flag with native up/down occupations, and `scheme=tm|ham` |
| OPIUM | Global/per-channel radii and `method`; reference configuration in the synthesized-input path |
| GTH | With `--refit`: Gaussian radii, atomic radii/domain, fitting weights and free/fixed radius masks |
| AtomPAW | Reference configuration, coupled radius scaling, matching radii by channel, compensation shape/local channel and energies of existing additional projectors |
| APE | Reference configuration, component radii/scaling, local channel, NLCC/core radius, component method and construction/eigensolver/ODE tolerances |
| ADPACK | Matching/local radii, NLCC, SCF mixing/threshold; grid, iterations/mixing method, native construction/local/projector/core settings and ghost search |

`--rcut-scale` cannot scale fhi98PP's implicit, internally computed default
radii. Set explicit `--channel-rc` values instead. GTH Gaussian widths are not
the same physical quantity as NC matching radii. Explicit GTH radii are fixed
in `FITPAR` unless the user explicitly frees them. Atomic `rcov/rprb` changes
update both atomic and fitting inputs. Custom GTH runs currently deliver the
GTH/CP2K representation: published CPMD/ABINIT variants are not substituted for
newly fitted coefficients. A second projector is required for an ONCVPSP
projector separation, and partial-core ratios require enabled core correction.
ONCVPSP basis size is checked against continuity order and projector count.
ADPACK 2.2 grid and SCF array limits are enforced, including for supplied
inputs; its upstream grid-limit check compares the wrong variable.
Imported coefficient blocks need an explicit matching `GTH-XC` header and use
the scalar table convention; a nonrelativistic construction requires fitting
from an explicit nonrelativistic atomic input. A coefficient block alone does
not identify the atomic solver that produced it. Typed native overrides add
a `-phys` checksum tag to generated names; imported files retain supplied-input
provenance and their archived checksums.

## What a successful run establishes

The native generator can reject a well-formed parameter choice: matching
conditions, root finding, overlap positivity and ghost checks impose additional
physical constraints. Such failures are retained, not replaced by another
recipe under the requested name. ADPACK and APE respect `--no-autofix`; detected
bound ghosts are rejected before delivery. A nonconverged ghost search does
not establish absence of ghosts. Numerical accuracy and transferability still
require independent checks for the intended material and property.
