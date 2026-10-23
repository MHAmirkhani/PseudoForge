# PseudoForge

A multi-engine pseudopotential generator, validator and reporting tool,
written entirely in Bash. The command-line tool drives nine atomic codes
— `ld1.x`, ONCVPSP, USPP, fhi98PP, OPIUM, GTH, AtomPAW, APE, ADPACK —
each for the families it generates, and `pw.x` for the cutoff convergence
scan. It has no Python, no compiled parts of its own and no dependencies
beyond coreutils and (optionally) `whiptail`.

```
pseudoforge generate -e Fe,Ni,Co -t paw -x pbe --cutoff-scan
```

---

## What it actually does

**Reproduces PSlibrary exactly.** PseudoForge ships the complete PSlibrary 1.0.0
recipe database — 567 generation recipes and 462 transferability test decks,
extracted from the upstream `.job` files. An untouched run reproduces the
upstream `ld1.x` deck **byte for byte** -- except for two caesium decks where upstream is physically impossible and the correction is declared in `data/psl/ERRATA.tsv` -- and `tests/test_psl_roundtrip.sh`
verifies that claim for every recipe across several functional and relativity
combinations on every test run.

**Lets you change the physics without editing input files.** Valence and
semicore configuration, core holes for XPS/XAS, fractional nuclear charge for
virtual-crystal pseudopotentials, NLCC, augmentation functions, extra
projectors, the local channel, the radial grid, SCF controls, GIPAW
reconstruction, UPF v2 — all from menus or command-line flags, all mapped
onto real `ld1.x` variables. Anything you do not touch stays byte-identical to
the library recipe.

**Runs the whole periodic table without babysitting.** Parallel execution,
resume, per-element failure isolation, and an auto-fix engine that retries a
failed element with a documented, physically motivated relaxation instead of
giving up.

**Validates what it produced.** Structural checks on every UPF, `ld1.x`
transferability tests against the all-electron atom, and an optional `pw.x`
kinetic-energy cutoff convergence scan. Results land in `summary.txt`,
`summary.csv`, `summary.json` and a self-contained `summary.html`.

---

## What it does not do, and why

PseudoForge drives nine atomic codes, and each has boundaries: what it
can generate, and what it refuses. Those boundaries are stated here rather
than papered over.

### Meta-GGA, hybrid and van der Waals functionals

`ld1.x` has no atomic solver for these families. Neither does any other public
library: SSSP, GBRV, SG15 and PseudoDojo all ship LDA and GGA pseudopotentials
and nothing else, and SCAN or HSE calculations are run with PBE-generated
pseudopotentials.

PseudoForge offers all of them anyway, and for each one records the semilocal
"generator functional" the community actually uses, generates with that, and
stamps the substitution into the log, the report and the run manifest:

```
$ pseudoforge recipe Si -t paw -x r2scan
WARN  r2SCAN (metaGGA) -- Quantum ESPRESSO ld1.x cannot generate this family; generated with
      Perdew-Burke-Ernzerhof instead. As SCAN; r2SCAN is the numerically better behaved variant.
```

The resulting file is honestly a PBE pseudopotential, is named as one, and is
the right thing to use for an r2SCAN calculation.

**Except with AtomPAW.** AtomPAW carries its own r2SCAN implementation
(`src/excor.F90`, `r2scanmod`), not libxc's, and `--engine atompaw
-x r2scan` produces a *real* meta-GGA PAW dataset — no proxy, no note, no
mislabelled GGA. It is non-relativistic only and writes PAW-XML and ABINIT,
not UPF (UPF has no field for the kinetic-energy density that makes a
meta-GGA a meta-GGA). See [the AtomPAW page](docs/reference/engines/atompaw.md).

---

## Generator engines

PseudoForge drives nine atomic codes. `ld1.x` comes with Quantum ESPRESSO; seven
PseudoForge compiles from source for you, and `adpack` is installed externally.

| engine | families | notes |
|---|---|---|
| `ld1` | NC US PAW | reproduces PSlibrary byte-identically (bar declared errata) |
| `oncvpsp` | NC | libxc-linked; no meta-GGA |
| `uspp` | US | Vanderbilt's own generator |
| `fhi98pp` | NC | Hamann and Troullier-Martins |
| `opium` | NC | widest format range |
| `gth` | NC | reproduces all 322 published GTH tables exactly |
| `atompaw` | PAW | the only meta-GGA engine |
| `ape` | NC | 28 of 28 elements |
| `adpack` | NC | OpenMX format; 29 of 29 bundled decks; external install |

```bash
pseudoforge engines list           # what is installed, what can be built
pseudoforge engines build all      # compile the 7 supported engines, record the paths
pseudoforge doctor                 # engines, converters, mirror, database
```

Put `oncvpsp-master.zip`, `uspp-734-3.tgz` and `fhi98PP.zip` beside the pseudoforge
directory and `engines build` finds them. Prerequisites on Ubuntu:

```bash
sudo apt-get install gfortran gcc make libblas-dev liblapack-dev unzip
```

An engine that is missing disables generation *with that engine* only —
importing and validating its files always works.

See [docs/reference/engines.md](docs/reference/engines.md) for what has to be patched to build
1990s Fortran with a current gfortran, and for the fhi98PP/UPF caveat.

## Download, or build locally

```bash
# download a published file, then validate it here
pseudoforge generate -e Si,Ge -p gbrv -t us --source online --cutoff-scan

# build locally with a named engine
pseudoforge generate -e Si,Ge -t nc --engine oncvpsp -x pbe --source local

# reproduce a published library from its own published inputs
pseudoforge generate -e Si -p pseudodojo -t nc --params ~/dojo-inputs/
```

`--source online` checks the library's official site first, then `MIRROR_URL`,
and runs the same validation over what arrives as over anything generated here.

**Owning the engine is not owning the parameters.** PseudoForge will run ONCVPSP for
you, but what makes SG15 "SG15" is its published table of cut-off radii and
projector counts. Without those inputs the result is labelled a pseudoforge
pseudopotential, never SG15 — see [docs/reference/data-provenance.md](docs/reference/data-provenance.md).

## Attribution

Every generated or downloaded pseudopotential carries its credit with it.
`CITATION.txt` and `LICENSE.txt` are written **into `pseudos/`**, beside the
`.UPF` files, so the attribution survives being copied into someone else's
`pseudo_dir`.

```bash
pseudoforge citation psl-high          # the reference for one library
pseudoforge citation --all             # everything PseudoForge knows
pseudoforge generate ... --attribution # a paste-ready block for a paper
```

`summary.html` gains a **References** section with resolvable DOI links.

Two rules govern `lib/metadata.sh`, and they matter more than the convenience:

- **Nothing is invented.** Each citation is the one the library's own authors
  ask for. Where PseudoForge has no citation it does not guess — it prints
  `Unverified -- check the source` with the project URL.
- **A DOI is recorded only when it belongs to the paper beside it.** DOIs
  resolve, so a wrong one is worse than none: it sends a reader somewhere
  confidently incorrect.

PseudoForge gives you the reference the authors asked for. It cannot know what your
journal wants, and it is not a substitute for checking.

## What can be generated, and what cannot

PseudoForge does not ship other people's parameter tables — but most libraries
publish their own generation inputs alongside the finished files, so it fetches
those and runs them. The result is a real reproduction, recorded with
provenance `library`, not a lookalike.

| library | how | provenance |
|---|---|---|
| PSlibrary (`psl-*`) | recipes ship with PseudoForge, byte-identical to upstream (bar declared errata) | `library` |
| SG15 | 86 ONCVPSP `.dat` decks from the source tarball | `library` |
| PseudoDojo | `.in` files from its GitHub repository, per functional and relativity | `library` |
| GBRV | the `Work_GBRV` uspp tree they generated from | `library` |
| Vanderbilt | `Work/` inside the uspp distribution PseudoForge builds | `vendor` |
| fhi98PP | `bin/Elements/{Ham,TM}` inside its own distribution | `vendor` |

```bash
pseudoforge params status            # what is held, what can be fetched
pseudoforge params fetch sg15        # or just generate and let it fetch
pseudoforge generate -e Si -p sg15 -t nc
```

Four are genuinely not reproducible, each for a stated reason:

- **HGH** — published fit coefficients, not generator output. There is no input
  deck and no atomic code that reproduces them.
- **SSSP** — a per-element *selection* from other libraries plus recommended
  cutoffs. Generate the library it selected for the element you want.
- **Wentzcovitch/VLab**, **Dacapo/CAMPOS** — distributed as finished files;
  no published generation inputs found.

These import cleanly and go through the same validation and reporting.

## Where downloads come from

`--source online` tries, in order, reporting each step:

1. **the library's official directory** — the authors' copy, definitive for the
   configuration asked for
2. **your mirror** (`MIRROR_URL`) — the fallback when upstream is unreachable
3. **neither** — it says which step failed and offers to generate locally

```
chain: official source -> mirror (https://pseudo.amirkhani.me/library/) -> generate locally
Si:
  [official] http://www.quantum-simulation.org/potentials/sg15_oncv/upf/Si_ONCV_PBE-1.2.upf
  found at the official source
```

A library distributed only as one archive (SG15's tarball, PseudoDojo's web
interface) has no addressable per-element URL, and PseudoForge does not invent
one — it tells you to fetch the archive and `import` it, or to generate.

## Making your own profiles and functionals

Both registries are user-extensible, and your additions live outside the
installation so an update cannot overwrite them:

```bash
pseudoforge profile new mylab --label "My lab NC set" --families nc --engine oncvpsp
pseudoforge xc add mygga --qe PBE --family GGA --label "My tuned GGA"
pseudoforge profile list
pseudoforge xc list
```

They land in `~/.pseudoforge/profiles/` and `~/.pseudoforge/xc.tsv`. A user file
with the same name as a shipped one overrides it deliberately.

## Install

```bash
git clone <your-repo> pseudoforge
cd pseudoforge
./pseudoforge doctor          # check the environment
```

Optionally put it on your `PATH`:

```bash
ln -s "$PWD/pseudoforge" ~/.local/bin/pseudoforge
```

Requirements:

| | |
|---|---|
| required | bash ≥ 4.0, coreutils, awk, sed, grep |
| to generate | Quantum ESPRESSO `ld1.x` |
| for cutoff scans | Quantum ESPRESSO `pw.x` |
| for the menus | `whiptail` (Debian/Ubuntu: `whiptail`, Fedora: `newt`, macOS: `brew install newt`) |

On first run PseudoForge writes `~/.pseudoforgerc`. Set `QE_ROOT_DIR` there, or set
`LD1_BIN` and `PW_BIN` directly.

```bash
pseudoforge config --set QE_ROOT_DIR=$HOME/q-e-7.4
pseudoforge doctor
```

---

## Use

### The wizard

```bash
pseudoforge
```

A six-step wizard — type, functional, relativity, library, source, elements — plus an
advanced screen for the physics and a review screen that prints the equivalent
command line before it runs anything.

### Command line

```bash
# a few elements, PAW/PBE, with a pw.x cutoff scan
pseudoforge generate -e Fe,Ni,Co -t paw -x pbe --cutoff-scan

# the whole low-cutoff ultrasoft library, 16 at a time
pseudoforge generate -e all -p psl-low -t us -j 16 -o ~/pp/pslow-pbe

# a core-hole pseudopotential for XPS
pseudoforge generate -e Cu --core-hole 1s --zval 12 -o ~/pp/cu-corehole

# a virtual-crystal site, half Al half Si
pseudoforge generate -e Si --zed 14.5 -o ~/pp/vca

# inspect the deck before committing to a long run
pseudoforge recipe Fe -t paw -p psl-high
```

Element selection accepts a lot more than symbols:

```
Fe,Si,O            symbols, names or atomic numbers
1-36               an atomic-number range
all                everything in the table
block:d            s | p | d | f
series:lanthanide  transition | actinide | halogen | noble | ...
period:4  group:16
transition-metals  lanthanides  actinides  main-group  magnetic  semiconductors
!Fe                exclude
```

### Other commands

```bash
pseudoforge list profiles           # what is available and where it came from
pseudoforge list functionals        # which are native, which are proxied
pseudoforge list recipes Fe         # every shipped recipe for one element
pseudoforge show psl-high           # a profile in full, with its element coverage
pseudoforge validate pseudos/*.UPF  # structural check of any UPF, from any source
pseudoforge import ~/sssp/          # register and test a third-party library
pseudoforge report <project>        # rebuild the reports of an existing project
pseudoforge doctor                  # environment and database check
```

---

## Output

Every run creates a project directory:

```
<project>/
  inputs/     the ld1.x decks that were used
  pseudos/    the .UPF files                     <- the deliverable
  tests/      transferability decks and cutoff scan data
  logs/       one log per element, plus PseudoForge.log
  reports/    summary.{txt,csv,json,html}
  manifest    the exact settings, down to the ld1.x version
  state.tsv   per-element status, so a re-run resumes
```

Installing is `cp pseudos/*.UPF $ESPRESSO_PSEUDO`.

The `manifest` is the reproducibility record: it holds every setting, the
resolved functional, whether that functional was native or proxied, and the
profile's provenance.

---

## Profiles

| profile | provenance | families | what it is |
|---|---|---|---|
| `psl-high` | generated | paw us nc | PSlibrary 1.0.0, most semicore, smallest radii, highest cutoff |
| `psl-low` | generated | paw us | PSlibrary 1.0.0 tuned for ~40 Ry |
| `psl-031` | generated | paw us | the older 0.1–0.3.1 recipes, for reproducing published work |
| `psl-alt` | generated | paw us | alternative valence choices |
| `psl-tot` | generated | paw us | upstream's untested extras (flagged in every report) |
| `sg15` | generated | nc | SG15 ONCV (Schlipf-Gygi), generated via ONCVPSP |
| `pseudodojo` | generated | nc paw | PseudoDojo standard sets, generated via ONCVPSP |
| `gbrv` | generated | us paw | GBRV (Garrity-Bennett-Rabe-Vanderbilt), generated via USPP |
| `cp2k-gth` | generated | nc | GTH (Goedecker-Teter-Hutter, CP2K), generated via GTH |
| `fhi` | generated | nc | FHI (fhi98PP), generated via fhi98PP |
| `vanderbilt` | generated | us | Vanderbilt ultrasoft classic, generated via USPP |
| `atompaw` | build engine | paw | AtomPAW (Holzwarth), PAW datasets including meta-GGA |
| `opium` | derived | nc | OPIUM (Rappe group), parameter-driven norm-conserving |
| `ape` | generated | nc | APE (Atomic Pseudopotential Engine), libxc-driven |
| `adpack` | generated | nc | ADPACK / OpenMX (Ozaki), OpenMX format, external install |
| `gipaw` | generated | us nc | GIPAW pseudopotentials (Ceresoli) |
| `hgh` | generated | nc | HGH (Hartwigsen-Goedecker-Hutter) |
| `pseudoforge-auto` | derived | paw us nc | PseudoForge's own construction for elements no library covers |
| `sssp` | selection | paw us nc | SSSP selection table (Standard Solid-State Pseudopotentials) |
| `dacapo` `nnin` `qe-legacy` `scan-tm` `vlab` `wentzcovitch` | import-only | — | validated and reported on, not regenerated |

`pseudoforge-auto` fills the gap above Z = 94, where PSlibrary stops. It adapts the
recipe of the same element from another set, or failing that from the nearest
same-group neighbour with cut-off radii scaled by the ratio of covalent radii.
It says so, in the log, in the UPF author field and in the report, and it forces
validation on. It is a starting point, not a curated set.

---

## The auto-fix engine

When `ld1.x` fails, PseudoForge classifies the error from the routine that raised it
and retries with a targeted relaxation rather than a random parameter jiggle:

| failure | first retry | second retry |
|---|---|---|
| augmentation functions (`find_qi`) | switch to Bessel augmentation | PSQ with a tighter matching radius |
| pseudo-wavefunction (`compute_chi`) | widen all cut-off radii by 5 % | widen by 12 % and soften the local channel |
| SCF non-convergence (`ascheq`) | damp the mixing to β = 0.1 | β = 0.05 and a looser threshold |
| radial grid (`do_mesh`) | extend `rmax` | extend and refine |
| local channel | build it from the all-electron potential | use l = 0 |
| inconsistent occupations | fall back to the tabulated ground state | — |

Whichever strategy worked is recorded in the report, so the result stays
reproducible. Elements that still fail go into the failure list and the batch
carries on.

---

## Validation

**Transferability** re-solves the pseudo-atom in configurations it was not
fitted to and compares against the all-electron atom, using PSlibrary's own test
decks where they exist. The worst eigenvalue error over all configurations is
graded:

| max &#124;dE&#124; | verdict |
|---|---|
| < 1 mRy | excellent |
| < 5 mRy | good |
| < 20 mRy | marginal |
| ≥ 20 mRy | poor — do not use without checking |

**Cutoff convergence** (`--cutoff-scan`) runs `pw.x` on a generic fcc elemental
cell across a ladder of `ecutwfc` values and reports the lowest cutoff at which
the total energy has stopped moving, to within `--cutoff-tol` mRy/atom. Cutoff
convergence is a property of the pseudopotential rather than of the particular
crystal, so a generic cell is a legitimate probe — but treat the number as a
starting point for your own system, not as a certificate.

---

## Tests

```bash
tests/run_tests.sh          # 172 checks against a mock ld1.x, no QE needed
tests/run_tests.sh --all    # 175 checks plus the full PSlibrary round-trip
```

`tests/test_psl_roundtrip.sh` regenerates every shipped recipe and diffs it
against the output of the upstream `.job` files. It is what backs the
"byte-identical" claim, and it must stay green.

---

## Documentation

- [docs/getting-started/quickstart.md](docs/getting-started/quickstart.md) — five minutes from nothing to a tested pseudopotential
- [docs/reference/wizard.md](docs/reference/wizard.md) — the guided flow, and the flag for every screen
- [docs/reference/engines.md](docs/reference/engines.md) — the nine generators, building them, and where parameters come from
- [docs/explanation/physics.md](docs/explanation/physics.md) — what every setting does, and how to choose an engine
- [docs/reference/data-provenance.md](docs/reference/data-provenance.md) — where every shipped number came from

## Credit

**PseudoForge** is written and maintained by **Mohammad H. Amirkhani**
(<https://amirkhani.me>), and distributed under the GNU GPL v2 or later.

Cite it as:

> M. H. Amirkhani, *PseudoForge: a multi-engine pseudopotential generator and
> validator*, version 1.3.2 (2026). <https://amirkhani.me>

A DOI has not been minted yet. When it is, set `MD_DOI[pseudoforge]` in
`lib/metadata.sh` and every citation PseudoForge prints picks it up. The suggested
archive title, so later references stay stable, is:

> **PseudoForge — a multi-engine pseudopotential generator and validator**

PseudoForge generates pseudopotentials using atomic codes it does not own.
Please cite the library you used and the generator that produced it as well —
`pseudoforge citation <library>` prints both, and `--attribution` gives you a block
ready to paste into a paper.

## Licence and attribution

PseudoForge is distributed under the GNU General Public License v2 or later.

The recipes in `data/psl/` are derived from **PSlibrary 1.0.0** by **Andrea Dal
Corso** (<https://dalcorso.github.io/pslibrary/>), also GPL-2.0-or-later. If you
publish results obtained with a `psl-*` profile, cite PSlibrary — PseudoForge is
only the harness that runs it. See [docs/reference/data-provenance.md](docs/reference/data-provenance.md).

`ld1.x` and `pw.x` are part of Quantum ESPRESSO
(<https://www.quantum-espresso.org>); cite it as its authors ask.
