# Concepts

Three things to understand before the choices make sense: what a
pseudopotential is decided by, which codes decide it, and how you talk to them.

## The ten layers

A pseudopotential is not one decision. It is ten, taken in order, and each
one constrains the ones after it. PseudoForge's full terminal user interface
(`pseudoforge tui`, or bare `pseudoforge`) walks them in this sequence, and the
command-line flags map onto them one for one.

The guided wizard (`pseudoforge wizard`) is a linear subset of these ten layers:
a six-step flow (`family` -> `xc` -> `rel` -> `profile` -> `source` -> `engine`,
with elements gathered along the way) focusing on the primary decisions and
defaulting the remaining layers (`format`, `validation`, `advanced`).

### 1. Formulation

**Norm-conserving (NC)**
: The pseudo wavefunction carries the same charge inside the cutoff radius as
  the all-electron one. Simple, transferable, and hard — high plane-wave
  cutoffs. Required by many codes and by most post-DFT methods (GW, BSE, TDDFT,
  EPW).

**Ultrasoft (US)**
: Norm conservation is relaxed and the missing charge is restored with
  augmentation functions. Much softer, so much cheaper, at the cost of a more
  complicated formalism and a higher charge-density cutoff.

**PAW**
: Keeps a formal link back to the all-electron wavefunction, so all-electron
  properties can be reconstructed. As soft as ultrasoft, and the default for
  most modern solid-state work. Needed for NMR, EFG and core-level
  spectroscopy.

### 2. Exchange-correlation functional

LDA, GGA, meta-GGA, hybrid. **The pseudopotential must be generated with the
same functional you will use in the solid**, because it encodes how the core
electrons screen the valence ones, and that screening is functional-dependent.
Using a PBE pseudopotential in an LDA calculation is a known and measurable
error, not a formality.

The exception, which is standard practice rather than a compromise: meta-GGA
and hybrid calculations are routinely done on GGA-generated pseudopotentials,
because most atomic codes have no meta-GGA path. PseudoForge says so in the
report when that is what happened. See [Choose a
functional](../how-to/choose-a-functional.md).

### 3. Relativity

`nonrel`, `scalar`, or `full`.

**Scalar-relativistic** includes the mass–velocity and Darwin terms and is the
right default for essentially everything above the first row. **Full**
(j-dependent) additionally splits by total angular momentum and is what you
need for spin-orbit coupling — heavy elements, topological materials, magnetic
anisotropy. It costs more and produces twice the projectors.

### 4. Elements

Which elements to build. Filtered by what the formulation, functional, and
relativity chosen above can actually make. Elements can be specified by symbol,
atomic number Z, range, chemical group, or exclusion.

### 5. Library profile

Whose published parameters to reproduce — PSlibrary, SG15, GBRV, PseudoDojo,
or PseudoForge's own construction (`pseudoforge-auto`). This determines the
core–valence partition (which electrons are frozen into the core and which are
valence or semicore) and default radii. See [Profiles](../reference/profiles.md).

### 6. Source

`local`, `online`, or `ask`. Download a published, verified file from the
upstream source or mirror, or build one with an atomic code on this machine.

### 7. Engine

Which atomic code runs the calculation. PseudoForge drives nine generator engines
(ld1.x, ONCVPSP, USPP, fhi98PP, OPIUM, GTH, AtomPAW, APE, ADPACK). Several can
make the same family, and they differ in numerical schemes and functional support.
See [Engines](../reference/engines.md).

### 8. Output format

What format the result is written as: UPF (v1 and v2), psp8, PAW-XML, `.vps`,
or CP2K/ABINIT formats. Not every engine writes every format; format converters
are invoked when supported. See [Formats](../reference/formats.md).

### 9. Validation

Transferability and cut-off checks after generation. Does it reproduce all-electron
eigenvalues in configurations it was not fitted to? Are there ghost states? What
plane-wave cutoff does it need? A file that exists is not a result. See
[Validation](../architecture/validation.md).

### 10. Advanced settings

Fine-grained parameter overrides: cutoff radii per channel (`--rcut-scale`),
the local channel (`--lloc`), local cutoff radius (`--rcloc`), extra projectors,
core hole configurations (`--core-hole`), nonlinear core corrections (`--nlcc`),
and solver relaxation with auto-fix retry logic.

---

## The nine engines

PseudoForge implements none of the methods above. It drives nine codes written
by the people who developed them.

| Engine | Families | Known for |
|---|---|---|
| [`ld1`](../reference/engines/ld1.md) | NC US PAW | Quantum ESPRESSO's atomic code; produces PSlibrary |
| [`oncvpsp`](../reference/engines/oncvpsp.md) | NC | Hamann's optimised norm-conserving; SG15, PseudoDojo |
| [`uspp`](../reference/engines/uspp.md) | US | Vanderbilt's original ultrasoft code |
| [`fhi98pp`](../reference/engines/fhi98pp.md) | NC | the FHI98 construction |
| [`opium`](../reference/engines/opium.md) | NC | the Rappe group's optimised method; many output formats |
| [`gth`](../reference/engines/gth.md) | NC | analytic Goedecker–Teter–Hutter coefficients for CP2K |
| [`atompaw`](../reference/engines/atompaw.md) | PAW | Holzwarth's PAW generator; the only real meta-GGA path |
| [`ape`](../reference/engines/ape.md) | NC | libxc-backed, a very wide functional range |
| [`adpack`](../reference/engines/adpack.md) | NC | Ozaki's generator for OpenMX |

Choosing an engine is usually implied by the other choices — asking for PAW
from PSlibrary means `ld1`, asking for SG15 means `oncvpsp` — and
`--engine` is there for when you want to override that. See [Choose an
engine](../how-to/choose-an-engine.md).

---

## The four interfaces

The same core, reached four ways.

**Command line (CLI)**
: `pseudoforge generate …`. Scriptable, reproducible, the interface that goes
  in shell scripts, Makefiles, and methods sections. Every layer and option is
  controlled via explicit flags.

**Terminal User Interface (TUI)**
: `pseudoforge tui` (also launched by a bare `pseudoforge`). An interactive,
  menu-driven terminal interface navigating all ten layers, configuration
  settings, engine status, and profile databases.

**Wizard**
: `pseudoforge wizard`. A guided linear flow through the six primary decisions
  (`family` -> `xc` -> `rel` -> `profile` -> `source` -> `engine`, with elements).
  The final review screen displays the exact CLI command your choices add up
  to, making the wizard an interactive way to learn the command line. See
  [The wizard](../reference/wizard.md).

**Local HTTP API**
: `pseudoforge api <method> <path>` (or the background HTTP server). Serves
  JSON endpoints for web frontends, REST clients, and automated CI pipelines.

All four interfaces call the exact same underlying library functions. No module
in `lib/` knows which interface is running, and none may print to stdout or
stderr directly — enforced by [the sink contract](../architecture/sink-contract.md).

---

## The project model

Every generation run produces a self-contained project directory (set via `-o DIR`,
defaulting to `./pseudoforge-output`):

```text
project/
├── PROVENANCE.txt     # Run metadata: tool version, engine binary, git build, parameters
├── manifest           # Manifest file recording generated outputs and checksums
├── state.tsv          # Element execution state for resumable batch runs
├── inputs/            # Generator decks supplied to or constructed for the engine
├── logs/              # Engine stdout/stderr streams and run logs
├── pseudos/           # Produced pseudopotentials, plus CITATION.txt and LICENSE.txt
├── reports/           # summary.{txt,csv,json,html} multi-format project summaries
└── tests/             # Transferability tests, inputs, outputs, and convergence data
```

In the native library store, an `index.tsv` catalogs every available pseudopotential
with metadata including element, functional, relativistic treatment, format, size,
and cryptographic SHA checksums.

---

## Structural validation versus physical verification

PseudoForge distinguishes between two kinds of checks, implemented by different
layers of the code:

**Structural validation (`pseudoforge validate`, `lib/validate.sh`)**
: Checks whether a pseudopotential file is syntactically well-formed, internally
  consistent, and physically plausible according to its format specification.
  It verifies that headers parse, radial grids are monotonic, the declared
  `z_valence` is positive and chemically reasonable, projector counts match
  `l_max`, and required augmentation blocks exist. This catches defective files
  that generator engines emit while exiting 0.

**Physical testing and verification (`lib/testing.sh`, `lib/validate.sh`)**
: Evaluates the physical validity and numerical quality of the pseudopotential
  itself:
  - **Transferability testing**: Solves the pseudo-atom in electronic
    configurations it was *not* fitted to (e.g. ionized or excited states) and
    compares eigenvalues, logarithmic derivatives, and total energies against
    all-electron atom calculations, while searching for unphysical ghost states.
  - **Cutoff convergence (`--cutoff-scan`)**: Computes energy and stress
    convergence across plane-wave kinetic energy cutoffs in a crystalline solid
    using `pw.x`.

Every transferability verdict is stamped with the exact engine and method that
measured it, because different generator codes use different numerical gauges
and criteria. See [Validation](../architecture/validation.md).

---

## Profiles, recipes and specifications

Three words that sound similar and are not.

**Profile**
: A published library — PSlibrary, SG15, GBRV. Its conventions and its
  citation. [Reference](../reference/profiles.md).

**Recipe (library sense)**
: One element's generation input within a profile. `pseudoforge recipe Fe`
  prints it.

**Recipe (saved sense)**
: Your own settings, saved by name and replayable.
  `pseudoforge recipe save …`. [Reference](../reference/recipes.md).

The overlap is unfortunate but both senses are established; PseudoForge keeps
them apart by subcommand — `recipe <element>` prints a deck, `recipe save`
stores a configuration — and no element symbol collides with a subcommand name.

---

Next: [Quick start](quickstart.md), or straight into
[Tutorial 1](../tutorials/01-carbon.md).
