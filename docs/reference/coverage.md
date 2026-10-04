# Coverage

Which profiles cover which elements, with what families, functionals and
formats. Two readers: a user who knows the element and wants the files, and
a user who knows the library and wants to see its range.

The tables below are generated from the profile registry and the element
table, so they describe what the shipped profiles *declare* they can
produce. What is *actually* in the pre-built store today is a separate
question, answered live:

- on the site, [download](https://pseudo.amirkhani.me/download/) lets you filter by element, family,
  functional and relativity;
- from the CLI, `pseudoforge native list` prints the index;
- over HTTP, `GET /api/native` returns the same in JSON.

## Reading the tables

*`Families`* is what the library itself publishes, not what every engine
can make. GBRV, for instance, publishes both ultrasoft and PAW sets; PseudoForge
drives it through the ultrasoft engine, so only `US` is generated from it and
the PAW tables are linked, not built.

*`Elements`* is a per-family count. `PAW:95 US:95 NC:92` on
psl-high means PSlibrary's high-accuracy set has recipes for 95 elements in
the PAW family, 95 in ultrasoft, and 92 in norm-conserving.

*A profile in the element table* is one whose inputs cover that element for
at least one of its families. The same element usually has several entries
because PseudoForge is deliberately not a single library: a user with a
Siesta code and a user with a CP2K code need different files for the same
element.

<!-- generated:begin -->
<!-- Do not edit between these markers: tools/gen_reference.sh writes them. -->

### Profiles and what they cover

| Profile | Engine | Families | Functionals | Elements |
|---|---|---|---|---|
| ADPACK / OpenMX (Ozaki) | adpack | NC | pz pbe | NC:0 |
| AtomPAW (Holzwarth) | atompaw | PAW | pbe pbesol pw r2scan | PAW:any |
| GTH (Goedecker-Teter-Hutter, CP2K) | gth | NC | pz pbe pbesol blyp bp olyp hcth120 hcth407 | NC:101 |
| Dacapo / CAMPOS | uspp | US | pz pbe | US:0 |
| FHI (fhi98PP) | fhi98pp | NC | pw | NC:any |
| GBRV (Garrity-Bennett-Rabe-Vanderbilt) | uspp | US PAW | pbe | US:64 PAW:64 |
| GIPAW pseudopotentials (Ceresoli) | ld1 | US NC | pbe | US:15 NC:1 |
| HGH (Hartwigsen-Goedecker-Hutter) | gth | NC | pz pbe pbesol blyp bp olyp hcth120 hcth407 | NC:101 |
| Marburg actinide PAW | ld1 | PAW | pbe | PAW:14 |
| NNIN/C Pseudopotential Virtual Vault (Cornell) | ld1 | NC US PAW | varies | NC:0 US:0 PAW:0 |
| OPIUM (Rappe group) | opium | NC | pbe pz | NC:any |
| PseudoDojo | oncvpsp | NC PAW | pbe pbesol pw | NC:63 PAW:63 |
| PseudoForge auto | ld1 | PAW US NC | pz pw vwn pbe pbesol pw91 bp blyp revpbe wc | PAW:103 US:96 NC:95 |
| PSlibrary 0.3.1 (legacy collection) | ld1 | PAW US | pz pw vwn pbe pbesol pw91 bp blyp revpbe wc | PAW:45 US:45 |
| PSlibrary 1.0.0 (alternative valence) | ld1 | PAW US | pz pw vwn pbe pbesol pw91 bp blyp revpbe wc | PAW:15 US:14 |
| PSlibrary 1.0.0 (high accuracy) | ld1 | PAW US NC | pz pw vwn pbe pbesol pw91 bp blyp revpbe wc | PAW:95 US:95 NC:92 |
| PSlibrary 1.0.0 (low cutoff) | ld1 | PAW US | pz pw vwn pbe pbesol pw91 bp blyp revpbe wc | PAW:52 US:52 |
| PSlibrary 1.0.0 (untested extras) | ld1 | PAW US | pz pw vwn pbe pbesol pw91 bp blyp revpbe wc | PAW:22 US:22 |
| Original Quantum ESPRESSO PP table | ld1 | NC US PAW | pz pbe | NC:0 US:0 PAW:0 |
| SCAN norm-conserving (Yao and Kanai) | oncvpsp | NC | scan | NC:0 |
| SG15 ONCV (Schlipf-Gygi) | oncvpsp | NC | pbe | NC:69 |
| SSSP (Standard Solid-State Pseudopotentials) | ld1 | PAW US NC | pbe pbesol | PAW:0 US:0 NC:0 |
| Vanderbilt ultrasoft (classic) | uspp | US | pw91 | US:any |
| VLab rare-earth PAW (Columbia) | ld1 | PAW | pbe | PAW:0 |
| Wentzcovitch / VLab | uspp | US PAW | pbe | US:0 PAW:0 |

### Formats and the engines that write them

| Format | Engines |
|---|---|
| `upf` (UPF (Quantum ESPRESSO v2)) | ld1 oncvpsp uspp opium atompaw ape |
| `psp8` (psp8 (ABINIT)) | oncvpsp |
| `fhi` (FHI / abinit) | opium |
| `recpot` (CASTEP recpot) | opium |
| `siesta` (SIESTA psf) | opium |
| `cpmd` (CPMD) | opium |
| `casino` (CASINO) | opium |
| `champ` (CHAMP) | opium |
| `teter` (Teter) | opium |
| `qso` (QSO / Qbox XML) | opium |
| `ncpp` (NCPP) | opium |
| `xml` (UPF XML schema) | ld1 oncvpsp uspp fhi98pp opium |
| `cpi` (cpi (FHI/abinit)) | fhi98pp |
| `uspp` (Vanderbilt .uspp) | uspp |
| `van` (Vanderbilt .van (ASCII)) | uspp |
| `gth` (GTH coefficients (CP2K)) | gth |
| `gth-cpmd` (GTH coefficients (CPMD)) | gth |
| `gth-abinit` (GTH coefficients (ABINIT)) | gth |
| `paw-abinit` (PAW dataset (ABINIT)) | atompaw |
| `paw-xml` (PAW-XML schema) | atompaw |
| `openmx` (OpenMX .vps) | adpack |
| `openmx-pao` (OpenMX pseudo-atomic orbitals) | adpack |

### Elements and the profiles that cover them

| Element | Profiles |
|---|---|
| H (Hydrogen) | `cp2k-gth` `gbrv` `hgh` `pseudodojo` `pseudoforge-auto` `psl-031` `psl-high` `sg15` |
| He (Helium) | `cp2k-gth` `hgh` `pseudodojo` `pseudoforge-auto` `psl-high` `sg15` |
| Li (Lithium) | `cp2k-gth` `gbrv` `hgh` `pseudoforge-auto` `psl-031` `psl-high` `psl-low` `sg15` |
| Be (Beryllium) | `cp2k-gth` `gbrv` `hgh` `pseudoforge-auto` `psl-alt` `psl-high` `psl-low` `sg15` |
| B (Boron) | `cp2k-gth` `gbrv` `hgh` `pseudodojo` `pseudoforge-auto` `psl-031` `psl-high` `sg15` |
| C (Carbon) | `cp2k-gth` `gbrv` `hgh` `pseudodojo` `pseudoforge-auto` `psl-031` `psl-high` `sg15` |
| N (Nitrogen) | `cp2k-gth` `gbrv` `hgh` `pseudodojo` `pseudoforge-auto` `psl-031` `psl-high` `sg15` |
| O (Oxygen) | `cp2k-gth` `gbrv` `hgh` `pseudodojo` `pseudoforge-auto` `psl-031` `psl-high` `psl-low` `sg15` |
| F (Fluorine) | `cp2k-gth` `gbrv` `hgh` `pseudodojo` `pseudoforge-auto` `psl-031` `psl-high` `sg15` |
| Ne (Neon) | `cp2k-gth` `hgh` `pseudodojo` `pseudoforge-auto` `psl-high` `psl-tot` `sg15` |
| Na (Sodium) | `cp2k-gth` `gbrv` `hgh` `pseudodojo` `pseudoforge-auto` `psl-031` `psl-high` `psl-low` `sg15` |
| Mg (Magnesium) | `cp2k-gth` `gbrv` `hgh` `pseudodojo` `pseudoforge-auto` `psl-alt` `psl-high` `psl-low` `psl-tot` `sg15` |
| Al (Aluminium) | `cp2k-gth` `gbrv` `gipaw` `hgh` `pseudodojo` `pseudoforge-auto` `psl-031` `psl-high` `psl-low` `sg15` |
| Si (Silicon) | `cp2k-gth` `gbrv` `hgh` `pseudodojo` `pseudoforge-auto` `psl-031` `psl-high` `psl-low` `sg15` |
| P (Phosphorus) | `cp2k-gth` `gbrv` `hgh` `pseudodojo` `pseudoforge-auto` `psl-031` `psl-high` `psl-low` `sg15` |
| S (Sulfur) | `cp2k-gth` `gbrv` `hgh` `pseudodojo` `pseudoforge-auto` `psl-031` `psl-high` `psl-low` `sg15` |
| Cl (Chlorine) | `cp2k-gth` `gbrv` `hgh` `pseudodojo` `pseudoforge-auto` `psl-031` `psl-high` `psl-low` `sg15` |
| Ar (Argon) | `cp2k-gth` `hgh` `pseudodojo` `pseudoforge-auto` `psl-031` `psl-high` `psl-low` `sg15` |
| K (Potassium) | `cp2k-gth` `gbrv` `hgh` `pseudodojo` `pseudoforge-auto` `psl-high` `psl-tot` `sg15` |
| Ca (Calcium) | `cp2k-gth` `gbrv` `hgh` `pseudodojo` `pseudoforge-auto` `psl-high` `psl-tot` `sg15` |
| Sc (Scandium) | `cp2k-gth` `gbrv` `hgh` `pseudodojo` `pseudoforge-auto` `psl-031` `psl-high` `sg15` |
| Ti (Titanium) | `cp2k-gth` `gbrv` `hgh` `pseudodojo` `pseudoforge-auto` `psl-high` `psl-tot` `sg15` |
| V (Vanadium) | `cp2k-gth` `gbrv` `hgh` `pseudodojo` `pseudoforge-auto` `psl-high` `psl-low` `psl-tot` `sg15` |
| Cr (Chromium) | `cp2k-gth` `gbrv` `hgh` `pseudodojo` `pseudoforge-auto` `psl-high` `psl-tot` `sg15` |
| Mn (Manganese) | `cp2k-gth` `gbrv` `hgh` `pseudodojo` `pseudoforge-auto` `psl-high` `psl-tot` `sg15` |
| Fe (Iron) | `cp2k-gth` `gbrv` `hgh` `pseudodojo` `pseudoforge-auto` `psl-031` `psl-alt` `psl-high` `psl-low` `sg15` |
| Co (Cobalt) | `cp2k-gth` `gbrv` `hgh` `pseudodojo` `pseudoforge-auto` `psl-alt` `psl-high` `psl-low` `psl-tot` `sg15` |
| Ni (Nickel) | `cp2k-gth` `gbrv` `hgh` `pseudodojo` `pseudoforge-auto` `psl-031` `psl-alt` `psl-high` `psl-low` `sg15` |
| Cu (Copper) | `cp2k-gth` `gbrv` `hgh` `pseudodojo` `pseudoforge-auto` `psl-031` `psl-high` `psl-low` `sg15` |
| Zn (Zinc) | `cp2k-gth` `gbrv` `hgh` `pseudodojo` `pseudoforge-auto` `psl-031` `psl-alt` `psl-high` `psl-low` `sg15` |
| Ga (Gallium) | `cp2k-gth` `gbrv` `hgh` `pseudoforge-auto` `psl-031` `psl-high` `psl-low` `sg15` |
| Ge (Germanium) | `cp2k-gth` `gbrv` `hgh` `pseudoforge-auto` `psl-031` `psl-high` `psl-low` `sg15` |
| As (Arsenic) | `cp2k-gth` `gbrv` `hgh` `pseudodojo` `pseudoforge-auto` `psl-031` `psl-alt` `psl-high` `psl-low` `sg15` |
| Se (Selenium) | `cp2k-gth` `gbrv` `hgh` `pseudodojo` `pseudoforge-auto` `psl-031` `psl-high` `psl-low` `sg15` |
| Br (Bromine) | `cp2k-gth` `gbrv` `hgh` `pseudodojo` `pseudoforge-auto` `psl-031` `psl-alt` `psl-high` `psl-low` `sg15` |
| Kr (Krypton) | `cp2k-gth` `hgh` `pseudodojo` `pseudoforge-auto` `psl-high` `psl-tot` `sg15` |
| Rb (Rubidium) | `cp2k-gth` `gbrv` `hgh` `pseudodojo` `pseudoforge-auto` `psl-high` `psl-tot` `sg15` |
| Sr (Strontium) | `cp2k-gth` `gbrv` `hgh` `pseudodojo` `pseudoforge-auto` `psl-031` `psl-high` `sg15` |
| Y (Yttrium) | `cp2k-gth` `gbrv` `hgh` `pseudodojo` `pseudoforge-auto` `psl-031` `psl-high` `sg15` |
| Zr (Zirconium) | `cp2k-gth` `gbrv` `hgh` `pseudodojo` `pseudoforge-auto` `psl-031` `psl-high` `sg15` |
| Nb (Niobium) | `cp2k-gth` `gbrv` `hgh` `pseudodojo` `pseudoforge-auto` `psl-031` `psl-high` `sg15` |
| Mo (Molybdenum) | `cp2k-gth` `gbrv` `hgh` `pseudodojo` `pseudoforge-auto` `psl-031` `psl-high` `sg15` |
| Tc (Technetium) | `cp2k-gth` `gbrv` `hgh` `pseudodojo` `pseudoforge-auto` `psl-031` `psl-high` `sg15` |
| Ru (Ruthenium) | `cp2k-gth` `gbrv` `hgh` `pseudodojo` `pseudoforge-auto` `psl-high` `psl-tot` `sg15` |
| Rh (Rhodium) | `cp2k-gth` `gbrv` `hgh` `pseudodojo` `pseudoforge-auto` `psl-031` `psl-high` `sg15` |
| Pd (Palladium) | `cp2k-gth` `gbrv` `hgh` `pseudodojo` `pseudoforge-auto` `psl-031` `psl-alt` `psl-high` `psl-low` `sg15` |
| Ag (Silver) | `cp2k-gth` `gbrv` `hgh` `pseudodojo` `pseudoforge-auto` `psl-031` `psl-alt` `psl-high` `psl-low` `sg15` |
| Cd (Cadmium) | `cp2k-gth` `gbrv` `hgh` `pseudodojo` `pseudoforge-auto` `psl-031` `psl-high` `psl-low` `sg15` |
| In (Indium) | `cp2k-gth` `gbrv` `hgh` `pseudodojo` `pseudoforge-auto` `psl-031` `psl-high` `sg15` |
| Sn (Tin) | `cp2k-gth` `gbrv` `hgh` `pseudodojo` `pseudoforge-auto` `psl-031` `psl-high` `sg15` |
| Sb (Antimony) | `cp2k-gth` `gbrv` `hgh` `pseudodojo` `pseudoforge-auto` `psl-alt` `psl-high` `psl-low` `psl-tot` `sg15` |
| Te (Tellurium) | `cp2k-gth` `gbrv` `hgh` `pseudodojo` `pseudoforge-auto` `psl-031` `psl-alt` `psl-high` `psl-low` `sg15` |
| I (Iodine) | `cp2k-gth` `gbrv` `hgh` `pseudodojo` `pseudoforge-auto` `psl-high` `psl-low` `sg15` |
| Xe (Xenon) | `cp2k-gth` `hgh` `pseudodojo` `pseudoforge-auto` `psl-high` `psl-tot` `sg15` |
| Cs (Caesium) | `cp2k-gth` `gbrv` `hgh` `pseudodojo` `pseudoforge-auto` `psl-high` `psl-low` `psl-tot` `sg15` |
| Ba (Barium) | `cp2k-gth` `gbrv` `hgh` `pseudodojo` `pseudoforge-auto` `psl-high` `psl-tot` `sg15` |
| La (Lanthanum) | `cp2k-gth` `gbrv` `gipaw` `hgh` `pseudodojo` `pseudoforge-auto` `psl-high` `sg15` |
| Ce (Cerium) | `cp2k-gth` `gipaw` `hgh` `pseudoforge-auto` `psl-high` `psl-low` |
| Pr (Praseodymium) | `cp2k-gth` `gipaw` `hgh` `pseudoforge-auto` `psl-high` `psl-low` |
| Nd (Neodymium) | `cp2k-gth` `gipaw` `hgh` `pseudoforge-auto` `psl-high` `psl-low` |
| Pm (Promethium) | `cp2k-gth` `gipaw` `hgh` `pseudoforge-auto` `psl-high` `psl-low` |
| Sm (Samarium) | `cp2k-gth` `gipaw` `hgh` `pseudoforge-auto` `psl-high` `psl-low` |
| Eu (Europium) | `cp2k-gth` `gipaw` `hgh` `pseudoforge-auto` `psl-high` `psl-low` |
| Gd (Gadolinium) | `cp2k-gth` `gipaw` `hgh` `pseudoforge-auto` `psl-high` `psl-low` |
| Tb (Terbium) | `cp2k-gth` `gipaw` `hgh` `pseudoforge-auto` `psl-high` `psl-low` |
| Dy (Dysprosium) | `cp2k-gth` `gipaw` `hgh` `pseudoforge-auto` `psl-high` `psl-low` |
| Ho (Holmium) | `cp2k-gth` `gipaw` `hgh` `pseudoforge-auto` `psl-high` `psl-low` |
| Er (Erbium) | `cp2k-gth` `gipaw` `hgh` `pseudoforge-auto` `psl-high` `psl-low` |
| Tm (Thulium) | `cp2k-gth` `gipaw` `hgh` `pseudoforge-auto` `psl-high` `psl-low` |
| Yb (Ytterbium) | `cp2k-gth` `gipaw` `hgh` `pseudoforge-auto` `psl-high` `psl-low` |
| Lu (Lutetium) | `cp2k-gth` `gipaw` `hgh` `pseudoforge-auto` `psl-high` `psl-low` |
| Hf (Hafnium) | `cp2k-gth` `gbrv` `hgh` `pseudodojo` `pseudoforge-auto` `psl-high` `psl-low` `sg15` |
| Ta (Tantalum) | `cp2k-gth` `gbrv` `hgh` `pseudodojo` `pseudoforge-auto` `psl-031` `psl-high` `psl-low` `sg15` |
| W (Tungsten) | `cp2k-gth` `gbrv` `hgh` `pseudodojo` `pseudoforge-auto` `psl-high` `psl-low` `psl-tot` `sg15` |
| Re (Rhenium) | `cp2k-gth` `gbrv` `hgh` `pseudodojo` `pseudoforge-auto` `psl-high` `psl-low` `psl-tot` `sg15` |
| Os (Osmium) | `cp2k-gth` `gbrv` `hgh` `pseudodojo` `pseudoforge-auto` `psl-high` `psl-low` `psl-tot` `sg15` |
| Ir (Iridium) | `cp2k-gth` `gbrv` `hgh` `pseudodojo` `pseudoforge-auto` `psl-031` `psl-alt` `psl-high` `psl-low` `sg15` |
| Pt (Platinum) | `cp2k-gth` `gbrv` `hgh` `pseudodojo` `pseudoforge-auto` `psl-031` `psl-alt` `psl-high` `psl-low` `sg15` |
| Au (Gold) | `cp2k-gth` `gbrv` `hgh` `pseudodojo` `pseudoforge-auto` `psl-031` `psl-alt` `psl-high` `psl-low` `sg15` |
| Hg (Mercury) | `cp2k-gth` `gbrv` `hgh` `pseudodojo` `pseudoforge-auto` `psl-031` `psl-high` `psl-low` `sg15` |
| Tl (Thallium) | `cp2k-gth` `gbrv` `hgh` `pseudoforge-auto` `psl-031` `psl-high` `sg15` |
| Pb (Lead) | `cp2k-gth` `gbrv` `hgh` `pseudoforge-auto` `psl-031` `psl-high` `sg15` |
| Bi (Bismuth) | `cp2k-gth` `gbrv` `hgh` `pseudoforge-auto` `psl-031` `psl-high` `sg15` |
| Po (Polonium) | `cp2k-gth` `hgh` `pseudoforge-auto` `psl-high` `psl-tot` |
| At (Astatine) | `cp2k-gth` `hgh` `pseudoforge-auto` `psl-high` `psl-tot` |
| Rn (Radon) | `cp2k-gth` `hgh` `pseudodojo` `pseudoforge-auto` `psl-high` `psl-tot` |
| Fr (Francium) | `pseudoforge-auto` `psl-high` |
| Ra (Radium) | `pseudoforge-auto` `psl-high` |
| Ac (Actinium) | `cp2k-gth` `hgh` `pseudoforge-auto` `psl-high` |
| Th (Thorium) | `cp2k-gth` `hgh` `marburg` `pseudoforge-auto` `psl-high` |
| Pa (Protactinium) | `cp2k-gth` `hgh` `marburg` `pseudoforge-auto` `psl-high` |
| U (Uranium) | `cp2k-gth` `hgh` `marburg` `pseudoforge-auto` `psl-high` |
| Np (Neptunium) | `cp2k-gth` `hgh` `marburg` `pseudoforge-auto` `psl-high` |
| Pu (Plutonium) | `cp2k-gth` `hgh` `marburg` `pseudoforge-auto` `psl-high` |
| Am (Americium) | `cp2k-gth` `hgh` `marburg` `pseudoforge-auto` `psl-high` |
| Cm (Curium) | `cp2k-gth` `hgh` `marburg` `pseudoforge-auto` |
| Bk (Berkelium) | `cp2k-gth` `hgh` `marburg` `pseudoforge-auto` |
| Cf (Californium) | `cp2k-gth` `hgh` `marburg` `pseudoforge-auto` |
| Es (Einsteinium) | `cp2k-gth` `hgh` `marburg` `pseudoforge-auto` |
| Fm (Fermium) | `cp2k-gth` `hgh` `marburg` `pseudoforge-auto` |
| Md (Mendelevium) | `cp2k-gth` `hgh` `marburg` `pseudoforge-auto` |
| No (Nobelium) | `cp2k-gth` `hgh` `marburg` `pseudoforge-auto` |
| Lr (Lawrencium) | `cp2k-gth` `hgh` `marburg` `pseudoforge-auto` |

<!-- generated:end -->

## Families the engines cannot make

Some libraries publish a family their engine cannot generate, because the
library's own datasets come from a different code. GBRV publishes PAW sets
produced elsewhere; PseudoDojo publishes PAW sets as well as its own NC
tables. Those are marked `import only` in the `profiles` table and the
site links to the authors' own copy rather than rehosting it.

## On the API

The coverage data behind these tables, as JSON:

```bash
curl -s https://pseudo.amirkhani.me/api/profiles | jq .
pseudoforge api GET /api/profiles
```

For what is in the store right now, `GET /api/native` is the endpoint — the
same data the site's download page filters.
