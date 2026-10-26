# The Advisory System

`pseudoforge advise` provides physics-reasoned guidance on which pseudopotential to choose for a specific calculation, rather than simply listing available files.

Different calculations require different pseudopotential characteristics: phonon dispersions and elastic constants demand high transferability and smooth potential derivatives; GW and optical spectra require accurate unoccupied states and multiple projectors; molecular dynamics benefits from softer cutoffs for performance; magnetic and correlated systems require explicit spin polarisation or semicore states.

---

## Synopsis

```bash
pseudoforge advise -e <element> [options]
```

### Options

| Option | Argument | Description |
|---|---|---|
| `-e, --element` | `NAME` | **Required.** Element symbol (`Fe`, `Si`, `U`, ...). |
| `--calculation` | `TYPE` | Calculation type (see [Calculation types](#calculation-types) below). Default: overview across all calculations. |
| `--code` | `CODE` | Target DFT code: `qe`, `abinit`, `vasp`, `cp2k`, `siesta`, `openmx`, `castep`. Affects format preference only. |
| `--material` | `CLASS` | Override auto-detected material class (see [Material classes](#material-classes) below). |
| `--functional` | `XC` | Override the functional chosen for the calculation (e.g. `pbe`, `pbesol`, `lda`). |
| `--accuracy` | `LEVEL` | `speed`, `balanced`, or `stringent`. Default depends on calculation (`stringent` for `gw` and `optics`, `balanced` for others). |
| `--json` | None | Emit structured JSON rather than formatted text. |
| `-q, --quiet` | None | Emit only the top recommended `pseudoforge generate` command line. |

---

## Calculation types

The 12 calculation IDs recognized by the advisory system:

| ID | Name | Default XC | Default Family | Default Accuracy | Physics considerations |
|---|---|---|---|---|---|
| `phonons` | Phonons & vibrational properties | `pbesol` | `nc` | `balanced` | Sensitive to potential softness; PBEsol provides accurate lattice constants and force constants. Soft potentials produce spurious imaginary modes. |
| `elastic` | Elastic constants & stress-strain | `pbesol` | `nc` | `balanced` | Requires accurate stress tensor and second energy derivatives with respect to strain. |
| `eos` | Equation of state & lattice parameter | `pbesol` | `paw` | `balanced` | PBEsol recovers accurate equilibrium volumes for solid-state crystals. PAW/USPP efficiency is preferred. |
| `band-gap` | Band structure & gap | `pbe` | `paw` | `balanced` | Standard ground-state electronic structure; standard PBE or HSE06 ground states. |
| `gw` | GW & quasiparticle spectra | `pbe` | `nc` | `stringent` | Requires accurate high-lying unoccupied states; multiple projector sets (stringent) are required to avoid completeness errors. |
| `optics` | Optical absorption & dielectric function | `pbe` | `nc` | `stringent` | Unoccupied conduction bands and transition dipole matrix elements require norm-conserving potentials with multiple projectors. |
| `xas` | X-ray absorption (XAS/XES) & core holes | `pbe` | `paw` | `balanced` | Core-hole generation requires PAW datasets with explicit core state unfreezing (`atompaw` or `ld1`). |
| `magnetism` | Magnetic ground states & spin | `pbe` | `paw` | `balanced` | Transition metals and lanthanides require spin polarisation and often semicore state inclusions. |
| `dft-u` | DFT+U & correlated electrons | `pbe` | `paw` | `balanced` | Localized d- and f-electron projections benefit from PAW projectors and Hubbard U corrections. |
| `md` | Molecular dynamics & high temperature | `pbe` | `paw` | `balanced` | Computational speed and smooth forces are paramount; softer cutoffs reduce trajectory integration cost. |
| `transport` | Electronic transport & Boltzmann equations | `pbe` | `paw` | `balanced` | Requires dense band velocity derivatives and reliable band curvatures. |
| `phonon-2d` | 2D materials & slab phonons | `pbe` | `nc` | `balanced` | Slabs with vacuum require norm-conserving potentials to avoid charge augmentation overlap issues in vacuum regions. |

---

## Material classes

Every element is automatically mapped to one of nine material classes:

1. `transition-metal` (Groups 3–12)
2. `lanthanide` (La–Lu)
3. `actinide` (Ac–Lr)
4. `alkali-metal` (Li, Na, K, Rb, Cs, Fr)
5. `alkaline-earth` (Be, Mg, Ca, Sr, Ba, Ra)
6. `halogen` (F, Cl, Br, I, At)
7. `noble-gas` (He, Ne, Ar, Kr, Xe, Rn)
8. `metalloid` (B, Si, Ge, As, Sb, Te)
9. `main-group` (Other p-block and s-block elements: H, C, N, O, Al, P, S, Ga, In, Sn, Tl, Pb, Bi, Po)

The material class can be explicitly overridden with `--material <class>`.

---

## Worked examples

### 1. Iron phonons (`Fe` + `phonons`)

Iron is a 3d transition metal with a magnetic ground state. Phonon calculations are notoriously sensitive to pseudopotential softness, frequently producing spurious imaginary frequencies at high symmetry points if the cutoff radii are too large.

```bash
pseudoforge advise -e Fe --calculation phonons
```

Output:

```text
=== PseudoForge Advisory System ===
Element:        Fe (Iron)
Material class: transition-metal
Calculation:    phonons (Phonons / vibrational properties)
Target code:    any

Top Recommendations:

#1  [Score 18]  PseudoDojo (nc, pbesol) via ONCVPSP (Hamann) [.upf]
    ⚡ Recommended cutoff: 90 Ry (SSSP efficiency)
    Why:
      PBEsol restores the correct gradient expansion for solids; lattice
      constants and phonon frequencies come out more accurate than with PBE.
      Norm-conserving keeps the calculation cheap.

      PseudoDojo's stringent NC sets have been validated against a phonon
      database for 3d transition metals. Iron, in particular, is known for
      soft modes if the pseudopotential is too soft.

      Iron has a magnetic ground state; spin polarisation must be on.

    Citations:
      - PseudoDojo: https://doi.org/10.1016/j.cpc.2018.01.012
      - ONCVPSP (Hamann): https://doi.org/10.1103/PhysRevB.88.085117

    Command:
      pseudoforge generate -e Fe -t nc -p pseudodojo -x pbesol -r scalar -o ./fe-run

#2  [Score 8]  PseudoForge auto (nc, pbesol) via Quantum ESPRESSO ld1.x [.upf]
#3  [Score 8]  PSlibrary 1.0.0 (high accuracy) (nc, pbesol) via Quantum ESPRESSO ld1.x [.upf]

⚠️  What to avoid for this calculation:
    - psl-low: PSLibrary's low-cutoff sets trade accuracy for speed. For phonons, that shows up as soft modes and imaginary frequencies.
    - psl-tot: psl-tot holds upstream's untested extras. Use it only when nothing else covers the element.

Related calculations for Fe:
    - magnetism: pseudoforge advise -e Fe --calculation magnetism
```

### 2. Silicon GW (`Si` + `gw`)

Quasiparticle GW calculations sum over hundreds of empty conduction bands. Standard pseudopotentials are constructed to reproduce only occupied valence eigenvalues; their scattering properties at high positive energy are uncontrolled unless multiple projectors are explicitly added.

```bash
pseudoforge advise -e Si --calculation gw
```

Output:

```text
=== PseudoForge Advisory System ===
Element:        Si (Silicon)
Material class: metalloid
Calculation:    gw (GW / quasiparticle calculations)
Target code:    any

Top Recommendations:

#1  [Score 18]  PseudoDojo (nc, pbe) via ONCVPSP (Hamann) [.upf]
    ⚡ Recommended cutoff: 30 Ry (SSSP efficiency)
    Why:
      Unoccupied states matter more than the lattice. Use stringent sets with
      multiple projectors.

      PseudoDojo's "stringent" NC sets have the multiple projectors that GW needs.

    Citations:
      - PseudoDojo: https://doi.org/10.1016/j.cpc.2018.01.012
      - ONCVPSP (Hamann): https://doi.org/10.1103/PhysRevB.88.085117

    Command:
      pseudoforge generate -e Si -t nc -p pseudodojo -x pbe -r scalar -o ./si-run
```

---

## REST API

The advisory system is available over the REST API via `GET` and `POST` requests to `/api/advise`:

```bash
curl "https://pseudo.amirkhani.me/api/advise?element=Fe&calculation=phonons&code=qe&accuracy=balanced"
```

or via POST with JSON body:

```bash
curl -X POST https://pseudo.amirkhani.me/api/advise \
     -H "Content-Type: application/json" \
     -d '{"element":"Fe","calculation":"phonons","code":"qe","accuracy":"balanced"}'
```
