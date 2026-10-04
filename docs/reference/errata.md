# Errata

The recipe database is sliced verbatim out of upstream PSlibrary's `.job`
files, and "verbatim" is the point — it is what lets PseudoForge say a deck is
PSlibrary's and mean it.

A handful of upstream decks are nevertheless **impossible**, in a way that makes
`ld1.x` produce a file no code can use. Those are corrected, and every
correction is declared in `data/psl/ERRATA.tsv`.

## The bar for a correction

A row is admissible only when the upstream value is **impossible, not merely
unusual**, and the correction is the minimal edit that removes the
impossibility.

Anything that is a matter of taste — an unusual radius, a valence partition you
disagree with, a projector count you would have chosen differently — stays
exactly as upstream wrote it. Those are the library authors' judgements, and
disagreeing with a judgement is not the same as finding an error.

## What is declared now

| set | element | keyword | upstream | corrected |
|---|---|---|---|---|
| `us-low` | Cs | `config` | `[Xe] 4f14 6s1 6p0 5d0` | `[Xe] 4f-1 6s1 6p0 5d0` |
| `paw-low` | Cs | `config` | `[Xe] 4f14 6s1 6p0 5d0` | `[Xe] 4f-1 6s1 6p0 5d0` |

Two decks. That is the whole list.

## The caesium case, worked through

### What upstream wrote

```text
config='[Xe] 4f14 6s1 6p0 5d0'
```

### Why it cannot be right

`[Xe]` is 54 electrons, and **xenon does not contain 4f** — the 4f shell first
fills at Z = 58, in the lanthanides. So `[Xe] 4f14` asks for

$$ 54 + 14 + 1 + 0 + 0 = 69 $$

electrons in an atom with Z = 55.

`ld1.x` does not object. It computes the core as everything not in the pseudo
list — 60 electrons — and reports

$$ z_{\text{valence}} = 55 - 60 = -5 $$

then writes the UPF and **exits 0**.

### How it was confirmed

Not by reading. The failing batch record was:

```text
Cs   ERROR: implausible z_valence=-5.0000000000000000
```

with an `ld1.x` log showing 47 SCF iterations and
`warning: at least one error in KS equations`. Running the unmodified upstream
deck reproduces all three signatures exactly — `z_valence = -5.00`, 47
iterations, the KS warning. That is what identifies this deck as the cause
rather than a plausible story about it.

### The correction

One token: `4f14` → `4f-1`.

A **negative occupation is `ld1.x`'s marker for an unoccupied channel**, and it
is what upstream itself writes for caesium in the *high* set
(`[Xe] 6s1 6p0 5d-1 4f-1`). So the correction is not an invention; it applies
upstream's own idiom for the same element.

Measured with QE 7.6:

| | upstream | corrected |
|---|---|---|
| `z_valence` | −5.00 | **9.00** (5s² 5p⁶ 6s¹) |
| SCF iterations | 47 | 27 |
| KS-equation warning | yes | no |
| AE−PS eigenvalue agreement | — | within 1×10⁻⁵ Ry |
| transferability | — | **excellent**, US and PAW |

The 4f channel is unoccupied and absent from the pseudo-wavefunction list, so
the corrected deck is **bit-for-bit identical** to dropping 4f altogether.

!!! warning "This is a physics-input change"
    It changes the all-electron reference configuration a recipe is generated
    from. It is admitted here, in `ERRATA.tsv`, in `CHANGELOG.md`, and in the
    `recipe.erratum` lines of every `PROVENANCE.txt` produced from a corrected
    recipe. It is not filed as a build fix.

## The counterexample: lanthanum

`data/psl/tests/paw-high/La.spfn.1.0.0.tpl` carries

```text
config='[Xe] 4f0 5d1.0 6s2 6p1'
```

which is 58 electrons for Z = 57 — a La⁻ anion.

**This is not corrected**, for two reasons:

1. It is faithful to upstream.
2. It is a **test** deck (`iswitch=2`), and a charged reference configuration
   is a legitimate transferability probe. Upstream ships several deliberately.

Inventing a parameter to tidy a number would be worse than the oddity. It is
recorded here and left alone.

## The file format

`data/psl/ERRATA.tsv`, tab-separated, `#` for comments:

| Column | Contents |
|---|---|
| `set` | recipe set as the extractor names it (`us-low`, `paw-high`, …) |
| `element` | element symbol |
| `tag` | variant tag (`spnl.1.0.0`, …) |
| `field` | the input keyword corrected |
| `upstream` | the **exact** upstream text |
| `corrected` | the exact replacement |
| `reason` | why upstream cannot be right, and what was measured |

The `reason` field is not decoration. It carries the measurement, so the claim
can be rechecked by someone who was not there.

## How it is applied

```bash
tools/extract_pslibrary.sh ~/pslibrary.1.0.0 data/psl
```

1. The errata are **copied out before the tree is wiped** — extraction begins
   with `rm -rf`, and `ERRATA.tsv` lives inside the tree it rebuilds.
2. Every deck is sliced verbatim.
3. The declared corrections are reapplied, and the extractor **fails loudly**
   if an upstream text no longer matches — that means upstream has changed and
   the claim needs rechecking, not that the correction should be skipped.
4. `check_configs` refuses to ship **any** generation deck whose configuration
   asks for more electrons than the nucleus has.

The rewrite is a literal splice, not a regex substitution: `sub()` would read
`[Xe]` as a character class, fail to match, and report the correction as
applied. That is not hypothetical — the first version of the patch did exactly
that.

## The gate

`check_configs` is the reason this page lists two decks rather than one. The
manual investigation found `us-low/Cs`; the sweep found `paw-low/Cs` as well.

It applies only to **generation** decks (`iswitch=3`). Test decks are exempt —
see lanthanum above. Negative occupations mark unoccupied channels and count as
zero.

## Why this exists at all

The caesium correction had **already been made once**, by hand, directly on the
extracted template — with no test, no changelog entry, and nothing to stop the
next extraction from silently reverting it, which it would have done.

Diffing the shipped tree against a fresh extraction found exactly two
hand-edits across 1,040 templates, both of them this correction, and nothing
recording that they existed.

A correction that lives only in a file is one `rm -rf` from gone.

## What it means for the byte-identical claim

The claim is **"byte-identical to upstream except exactly where `ERRATA.tsv`
declares otherwise"**, and `tests/test_psl_roundtrip.sh` enforces exactly that:
it renders every deck twice — once by sourcing upstream, once from the shipped
database — and fails on any difference that is not declared, and on any
declared difference that has stopped appearing.

```text
  PASS  gen-pbe-scalar        565 decks, 2 differing only where ERRATA declares
  PASS  gen-pbe-full          565 decks, 2 differing only where ERRATA declares
  PASS  gen-pz-scalar         565 decks, 2 differing only where ERRATA declares
  PASS  test-pbe-scalar       462 decks byte-identical
  PASS  test-pbe-full         462 decks byte-identical
```

That is a stronger claim than "byte-identical", and a checkable one.

## In your output

A run that used a corrected recipe says so:

```bash
grep erratum ./out/PROVENANCE.txt
```

```text
recipe.erratum=us-low Cs spnl.1.0.0: config corrected from [Xe] 4f14 6s1 6p0 5d0 to [Xe] 4f-1 6s1 6p0 5d0
recipe.erratum.reason=[Xe] is 54 electrons and does not contain 4f, which first fills at Z=58; ...
```

A run that used none says nothing.
