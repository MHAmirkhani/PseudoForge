# Library profiles

A **profile** is a published pseudopotential library: its recipes, its
conventions, its provenance and its citation. Choosing a profile is choosing
whose judgement about radii, valence partitions and projector counts you are
adopting.

The table is generated from the profile registry, so it lists what is actually
installed rather than what was installed when this page was written.

<!-- generated:begin -->
<!-- Do not edit between these markers: tools/gen_reference.sh writes them. -->

| Profile | Library | Families | Recipes ship here |
|---|---|---|---|
| `adpack` | ADPACK / OpenMX (Ozaki) | NC | yes |
| `atompaw` | AtomPAW (Holzwarth) | PAW | yes |
| `cp2k-gth` | GTH (Goedecker-Teter-Hutter, CP2K) | NC | yes |
| `dacapo` | Dacapo / CAMPOS | US | import only |
| `fhi` | FHI (fhi98PP) | NC | yes |
| `gbrv` | GBRV (Garrity-Bennett-Rabe-Vanderbilt) | US PAW | yes |
| `gipaw` | GIPAW pseudopotentials (Ceresoli) | US NC | yes |
| `hgh` | HGH (Hartwigsen-Goedecker-Hutter) | NC | yes |
| `marburg` | Marburg actinide PAW | PAW | yes |
| `nnin` | NNIN/C Pseudopotential Virtual Vault (Cornell) | NC US PAW | import only |
| `opium` | OPIUM (Rappe group) | NC | yes |
| `pseudodojo` | PseudoDojo | NC PAW | yes |
| `pseudoforge-auto` | PseudoForge auto | PAW US NC | yes |
| `psl-031` | PSlibrary 0.3.1 (legacy collection) | PAW US | yes |
| `psl-alt` | PSlibrary 1.0.0 (alternative valence) | PAW US | yes |
| `psl-high` | PSlibrary 1.0.0 (high accuracy) | PAW US NC | yes |
| `psl-low` | PSlibrary 1.0.0 (low cutoff) | PAW US | yes |
| `psl-tot` | PSlibrary 1.0.0 (untested extras) | PAW US | yes |
| `qe-legacy` | Original Quantum ESPRESSO PP table | NC US PAW | import only |
| `scan-tm` | SCAN norm-conserving (Yao and Kanai) | NC | import only |
| `sg15` | SG15 ONCV (Schlipf-Gygi) | NC | yes |
| `sssp` | SSSP (Standard Solid-State Pseudopotentials) | PAW US NC | import only |
| `vanderbilt` | Vanderbilt ultrasoft (classic) | US | yes |
| `vlab` | VLab rare-earth PAW (Columbia) | PAW | import only |
| `wentzcovitch` | Wentzcovitch / VLab | US PAW | import only |

<!-- generated:end -->

---

## "Recipes ship here" — what it means

**yes**
: The library's own generation inputs are shipped with PseudoForge, and running
  a generation reproduces the library's published file from its own recipe.
  Nothing is downloaded.

**import only**
: The library publishes files but not the inputs that made them, or the inputs
  are not redistributable. PseudoForge can fetch, register and validate the
  files, but it cannot regenerate them, and it does not pretend to. Use
  `pseudoforge import` or `--source online`.

**selection**
: The library is a *choice* among other libraries rather than a library of its
  own — SSSP is a curated table saying "for this element, use this file from
  this other library, at this cutoff". PseudoForge follows the choice and
  records which underlying library each file came from.

## The PSlibrary family

Five of the profiles are PSlibrary 1.0.0 sets, and the differences matter:

| Profile | What it is |
|---|---|
| `psl-high` | The high-accuracy set. More projectors, harder, the default. |
| `psl-low` | The low-cutoff set. Softer, cheaper, fewer projectors. |
| `psl-031` | The legacy 0.3.1 collection, kept for reproducing older work. |
| `psl-alt` | Alternative valence partitions — a different choice of what is semicore. |
| `psl-tot` | Extras upstream ships without testing. Treat accordingly. |

Recipes for these are **byte-identical to upstream's own `.job` files except
where [`ERRATA.tsv`](errata.md) declares a correction**, which at present is
two decks, both caesium. `tests/test_psl_roundtrip.sh` renders every deck twice
— once by sourcing upstream, once from the shipped database — and fails on any
difference that is not declared.

## `pseudoforge-auto`

The one profile that is not a published library. Where no library covers an
element in the family you asked for, PseudoForge can build a recipe from a
neighbouring element plus a documented radius heuristic. It is marked
`derived` everywhere it appears, the report carries a note, and the generated
files are tagged so they cannot be mistaken for a library's.

Use it to get something to test with. Do not use it and call it PSlibrary.

## Inspecting a profile

```bash
pseudoforge list profiles              # all of them, with coverage
pseudoforge show psl-high              # full description and citation
pseudoforge list recipes Fe            # every recipe any profile has for Fe
pseudoforge list sets                  # the PSlibrary sets and their sizes
```

`pseudoforge recipe <element>` prints the exact deck that would be generated,
which is the fastest way to see what a profile's choices are for one element
before committing to a run.

---

## On the API

```bash
curl -s https://pseudo.amirkhani.me/api/profiles
pseudoforge api GET /api/profiles
```

See the [HTTP API reference](http-api.md).
