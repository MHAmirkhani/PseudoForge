# Provenance of the data PseudoForge ships

This file records exactly where every number in `data/` came from, because a
pseudopotential tool that is vague about that is not usable for published work.

---

## `data/psl/` — PSlibrary 1.0.0 recipes

**Source:** PSlibrary 1.0.0 by Andrea Dal Corso,
<https://dalcorso.github.io/pslibrary/>
**Licence:** GNU General Public License v2 or later
**How it got here:** mechanically, by `tools/extract_pslibrary.sh`.

The upstream distribution is a set of Bash scripts (`paw_ps_high.job`,
`us_ps_low.job`, `nc_ps_collection.job`, …) that emit `ld1.x` input decks through
here-documents. The extractor slices each here-document out verbatim and stores
it as a template with four placeholders:

| placeholder | upstream variable | meaning |
|---|---|---|
| `{{FCT}}` | `$fct` | functional tag used in file names (`pbe`, `rel-pbe`, …) |
| `{{GFUN}}` | `$gfun` | the `dft=` string handed to `ld1.x` |
| `{{NREL}}` | `$nrel` | `rel=` (1 scalar, 2 full) |
| `{{PSDIR}}`, `{{FROZEN_CORE}}` | `$psdir`, `$frozen_core` | test decks only |

Nothing else is altered. No radius, occupation, projector energy or namelist
keyword is edited, reformatted or "improved" — with one declared exception,
described under *Errata* below.

### Errata: where we knowingly differ from upstream

A very small number of upstream decks are not merely unusual but **impossible**,
and produce a file that `ld1.x` writes successfully and no code can use. Those
are corrected, and every correction is declared in `data/psl/ERRATA.tsv` with
the set, element, variant, keyword, the exact upstream text, the replacement,
and the reason with the measurement behind it.

The bar for a row is deliberately high: the upstream value must be impossible,
not just surprising, and the correction must be the minimal edit that removes
the impossibility. Anything that is a matter of taste stays exactly as upstream
wrote it.

Currently declared:

| set | element | keyword | upstream | corrected |
|---|---|---|---|---|
| `us-low` | Cs | `config` | `[Xe] 4f14 6s1 6p0 5d0` | `[Xe] 4f-1 6s1 6p0 5d0` |
| `paw-low` | Cs | `config` | `[Xe] 4f14 6s1 6p0 5d0` | `[Xe] 4f-1 6s1 6p0 5d0` |

`[Xe]` is 54 electrons and does not contain 4f — 4f first fills at Z=58 — so
`[Xe] 4f14` asks for 68 electrons in an atom with Z=55. `ld1.x` counts a core
of 60, reports `z_valence = 55 − 60 = −5` and exits 0. `4f-1` is ld1's marker
for an unoccupied channel and is what upstream itself writes for Cs in the high
set; measured, it gives `z_valence = 9.00`, transferability *excellent*, and a
result bit-for-bit identical to dropping 4f altogether. See `CHANGELOG.md` for
the full measurement.

Three things make this a declaration rather than a hand-edit:

- The extractor **reapplies** the errata on every run, and fails loudly if an
  upstream text no longer matches — which would mean upstream has changed and
  the claim needs rechecking.
- Extraction **refuses** to ship any generation deck (`iswitch=3`) whose config
  asks for more electrons than the nucleus has, so the next defect of this
  class cannot pass silently. Test decks (`iswitch=2`) are exempt: a charged
  reference configuration is a legitimate transferability probe.
- Any run that used a corrected recipe says so in its `PROVENANCE.txt`, as
  `recipe.erratum` and `recipe.erratum.reason`.

This exists because the Cs correction had already been made once by hand,
directly on the extracted template — and extraction begins with `rm -rf`, so
the next run of the extractor would have silently reverted it.

### Two upstream subtleties the extractor preserves

**Relativity-conditional recipes.** Some 0.3.1-era recipes sit inside
`if [ $nrel = 2 ] … else … fi`, so the deck differs between scalar- and
full-relativistic runs. Those are stored as separate templates and the index
records which branch each belongs to (`fr`, `sr`, or `any`); PseudoForge selects the
correct one automatically.

**Per-set `frozen_core`.** The `_low` test sets run with `frozen_core=.true.`,
the others with `.false.`. That default is recorded per set in
`data/psl/tests/<set>.frozen_core`.

### The correctness claim, and how it is checked

`tests/test_psl_roundtrip.sh` materialises every deck twice — once by sourcing
the upstream `.job` files in a shell, once by rendering PseudoForge's database — and
diffs the two trees. It currently verifies:

| check | decks |
|---|---|
| generation, `pbe`, scalar | 565 |
| generation, `rel-pbe`, full | 565 |
| generation, `pz`, scalar | 565 |
| transferability tests, `pbe`, scalar | 462 |
| transferability tests, `rel-pbe`, full | 462 |

byte-identical to upstream **except exactly where `ERRATA.tsv` declares
otherwise** — an undeclared difference fails the test. If you change anything
under `data/psl/` or in the extractor, this test is the thing that must stay
green.

### What is *not* included

`paw_lan_collection.job`, `us_lan_collection.job` and `obsolete.job` are
commented out in their entirety upstream and marked obsolete in the
`AAREADME` ("the PPs have been moved to paw_ps_low and corrected"). They are not
extracted.

---

## `data/elements/table.tsv` — the periodic table

Columns: `Z`, symbol, name, period, group, block, series, standard atomic
weight, ground-state configuration, covalent radius.

* **Standard atomic weights** are the IUPAC conventional values; for elements
  with no stable isotope, the mass number of the longest-lived one. They are used
  only for `ATOMIC_SPECIES` in the `pw.x` cutoff-scan cells, where the value does
  not affect a static SCF energy.
* **Ground-state configurations** are the experimental neutral-atom
  configurations, including the usual anomalies (Cr, Cu, Nb, Mo, Ru, Rh, Pd, Ag,
  La, Ce, Gd, Pt, Au, Ac, Th, Pa, U, Np, Cm, Lr). They are used as a fallback
  configuration by the auto-fix engine and as the occupation source for
  `pseudoforge-auto`.
* **Covalent radii** are the Cordero *et al.* (Dalton Trans., 2008, 2832) values.
  Values for the heaviest actinides are estimates. They are used **only** to
  scale cut-off radii in the `pseudoforge-auto` profile and to size the generic fcc
  cell in the cutoff scan. Nothing in a `psl-*` run depends on them.

---

## `data/xc.tsv` — the functional registry

Each row records the QE `dft=` short name, the family, whether `ld1.x` can
generate that family (`native`) or not (`proxy`), and for proxies the semilocal
functional pseudoforge generates with instead.

The proxy choices follow ordinary community practice rather than anything
PseudoForge invented:

| functional | generated with | why |
|---|---|---|
| TPSS, revTPSS, SCAN, r2SCAN, M06-L, TB09 | PBE | meta-GGA calculations are routinely run on PBE pseudopotentials |
| PBE0, HSE, SCAN0, Gau-PBE | PBE | hybrid runs use the semilocal parent's pseudopotential |
| B3LYP, X3LYP | BLYP | BLYP is their semilocal parent |
| vdW-DF | revPBE | revPBE *is* vdW-DF's exchange |
| optB88-vdW | optB88 | likewise, and `OPTBK88` is available in `ld1.x` |
| vdW-DF2-B86R | optB86b | likewise |
| vdW-DF2, vdW-DF-cx, rVV10 | PBE | their exchange (rPW86, LV-PW86r) is not separately available in `ld1.x` |

One deliberate detail: `pz` writes `dft='LDA'`, not `dft='PZ'`. QE's `LDA` short
name expands to `sla+pz`, i.e. Perdew–Zunger — the same functional — and `LDA` is
what PSlibrary's own `pz` environment writes. Matching it keeps those decks
byte-identical.

---

## `data/profiles/` — the library registry

Each `.profile` file is a plain `key=value` description: label, families,
provenance, generating code, upstream project, author, reference URL and
licence.

`provenance` is the field that matters:

| value | meaning |
|---|---|
| `native` | pseudoforge generates it with `ld1.x` from recipes identical to the published library's own inputs |
| `derived` | PseudoForge builds the recipe itself, from a documented heuristic; not a reproduction of anyone's library |
| `external` | produced by a different generator, or a curated selection; pseudoforge imports and validates, and does not claim to recreate it |

For the `external` profiles, PseudoForge deliberately ships **no** parameter tables.
Publishing a file that carries a trusted library's name but not its numbers would
be worse than shipping nothing, so the entries carry the attribution, the
generating code and the reason `ld1.x` cannot reproduce them — and the import
path instead.

If you have an official cutoff table (for example the SSSP JSON from Materials
Cloud), drop it in and point `cutoff_table=` at it; PseudoForge will use those
cutoffs for tests and reports rather than its own scan.

---

## Engine source archives and their parameter databases

PseudoForge can build engines from source and, for the three that ship one
(ONCVPSP, USPP, fhi98PP), uses the per-element parameter database that comes
with them. Those databases are the authors' own published work, not
PseudoForge's:

| engine | database | status |
|---|---|---|
| ONCVPSP | `tests/data/<NN>_<El>.dat` | Hamann's regression decks — real, citable inputs |
| USPP | `Work/<NNN>-<El>/*.adat` | Vanderbilt's own per-element decks |
| fhi98PP | `bin/Elements/{Ham,TM}/*.ini` | the FHI database, whose README warns "do not use uncritically" |

Nothing from these trees is redistributed with PseudoForge. They are read from the
source archive you supply, under the licence each carries:

- ONCVPSP — GPL-3.0, <https://github.com/oncvpsp/oncvpsp>
- USPP — GPL-2.0-or-later, <https://www.physics.rutgers.edu/~dhv/uspp/>
- fhi98PP — see the licence inside the distribution,
  <https://th.fhi-berlin.mpg.de/th/fhi98md/fhi98PP/>

### The one thing pseudoforge generates itself

When no library table and no vendor deck exists for an element, PseudoForge builds
an ONCVPSP deck from the element's ground-state configuration, with cut-off
radii scaled from the covalent radius and two projectors per channel. Such a
file is stamped `pseudoforge` in `state.tsv`, in every report, and in a comment at
the top of the input deck itself:

```
# NOT a published parameter set: built from the ground-state
# configuration of Si with PseudoForge cut-off radii.  Validate it
# (ghost check, cutoff scan, transferability) before using it.
```

This construction is a starting point, and it is not always a good one. In
testing it produced ghost states for oxygen and failed outright for iron, while
the vendor decks for the same elements worked immediately. That is the expected
shape of the problem — choosing radii and projector counts *is* the hard part of
making a pseudopotential, which is exactly why curated libraries have value and
why PseudoForge will not pretend to have reproduced one.

### What PseudoForge refuses to do

Run the right engine and call the result by a library's name without that
library's parameters. Asking for SG15 with ONCVPSP installed but no SG15 inputs
produces a loud warning and a file labelled `pseudoforge`, never `sg15`. With
`--params` pointing at the published inputs, it produces a real reproduction and
labels it `library`.

The distinction is recorded in `state.tsv` column 6 and in every report, so a
file's provenance survives being copied out of the project directory.

## Citations and licences (`lib/metadata.sh`)

`MD_VERIFIED` records which of three things is true, and each prints
differently, because they mean different things to someone writing a
bibliography:

| value | meaning | prints as |
|---|---|---|
| `yes` | the authors ask for this citation, in their distribution or on their publication page | the citation and its DOI |
| `no-request` | the authors ask for nothing — checked, not assumed — and this is the reference their *own* documentation gives for the method | `No citation request from the authors (checked: …). Method reference from their own documentation: …` |
| `no` | not established | `Unverified -- check the source` with a TODO naming what to check |

`no-request` exists because presenting a method paper as a request would put
words in the authors' mouths. ADPACK, AtomPAW and OPIUM are all `no-request`:
none of the three asks for a citation anywhere — distribution, manual or
website — and each entry names the document the reference was taken from.
Every DOI recorded was resolved to the title beside it.

Currently unverified, and deliberately so: **Wentzcovitch/VLab** and
**Dacapo/CAMPOS**, which PseudoForge knows as distributions but has no citation it
can stand behind, and **pseudoforge-auto**, which is not a published library at all
-- for that one there is nothing to cite but the engine that ran and the recipe
it was adapted from, both recorded in the UPF header and the run manifest.

Some ids are the same reference under another name: citing `ld1` means citing
Quantum ESPRESSO, citing the `uspp` code means citing the Vanderbilt paper.
`md_canon_id` normalises these before de-duplication so one work cannot appear
twice in a reference list.

## Citing

Using a `psl-*` profile means you used PSlibrary. Cite it:

> A. Dal Corso, *Pseudopotentials periodic table: From H to Pu*,
> Comput. Mater. Sci. **95**, 337 (2014).

and Quantum ESPRESSO for `ld1.x` / `pw.x`:

> P. Giannozzi *et al.*, J. Phys.: Condens. Matter **21**, 395502 (2009);
> J. Phys.: Condens. Matter **29**, 465901 (2017).

PseudoForge itself is a harness. Mention it if it helped, but the physics belongs to
the libraries and to the atomic code.
