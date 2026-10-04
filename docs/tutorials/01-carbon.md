# 1. Carbon, the simplest case

Carbon is the right place to start because almost nothing about it is
complicated. Six electrons, two of them core, no semicore states, no d
electrons in the valence, no relativistic effects worth worrying about. What
you learn here is the *shape* of a PseudoForge run, which is the same for
every element afterwards.

You will also learn something the happy path would hide: why the
transferability column can come back empty, and why PseudoForge prints a dash
there instead of a grade.

## What we are asking for

```bash
mkdir -p ~/pf-tutorials && cd ~/pf-tutorials
pseudoforge generate -e C -t nc -p psl-high -x pbe -o ./01-carbon
```

Four decisions, and each one is a layer from [Concepts](../getting-started/concepts.md):

`-e C`
: Carbon.

`-t nc`
: **Norm-conserving.** For a first pseudopotential this is the right
  formulation to meet: it is the simplest construction, and it is the one
  required by GW, BSE, TDDFT and EPW. Carbon has no semicore problem and only
  four valence electrons, so the usual objection to norm-conserving — that it
  is expensive — barely applies. For a production plane-wave calculation on a
  carbon-containing solid you would more likely reach for PAW, as in
  [tutorial 3](03-iron.md).

`-p psl-high`
: **PSlibrary 1.0.0, high-accuracy set.** We are reproducing a published
  recipe rather than inventing one. `psl-high` is the default and the more
  accurate of the two main PSlibrary sets; `psl-low` trades accuracy for a
  lower plane-wave cutoff.

`-x pbe`
: **PBE.** The most widely used GGA for solids. The functional here must match
  the functional in the calculation you are going to run — see
  [Choose a functional](../how-to/choose-a-functional.md).

## What happens

```text
== PseudoForge 1.3.0 ==
INFO  profile    PSlibrary 1.0.0 (high accuracy)  [generated]
INFO  family     NC   functional PBE   Scalar-relativistic (no spin-orbit)
INFO  elements   1: C
INFO  project    ./01-carbon

== Generating ==
INFO  generating 1 element(s) with 4 parallel job(s)
OK    C  ->  C.pbe-nc.UPF  (1s)

== Transferability tests (ld1.x, iswitch=2) ==
INFO  wrote CITATION.txt and LICENSE.txt to ./01-carbon/pseudos

== Reports ==
INFO  text : ./01-carbon/reports/summary.txt
INFO  csv  : ./01-carbon/reports/summary.csv
INFO  json : ./01-carbon/reports/summary.json
INFO  html : ./01-carbon/reports/summary.html
INFO  prov : ./01-carbon/PROVENANCE.txt
```

Note `Scalar-relativistic` although we never asked for it. That is the default,
and it is the right default: scalar-relativistic costs nothing extra and is
correct for everything above the first row. For carbon it makes almost no
difference; for gold it makes a large one.

Then the summary:

```text
 project      : ./01-carbon
 profile      : PSlibrary 1.0.0 (high accuracy) (generated)
 family       : NC
 functional   : Perdew-Burke-Ernzerhof (GGA) -- generated natively by Quantum ESPRESSO ld1.x as dft=PBE
 relativity   : Scalar-relativistic (no spin-orbit)
 UPF format   : v2
 engine       : Quantum ESPRESSO ld1.x v.7.6 [build 7de3694ef3fd] /opt/espresso/7.6/ld1.x
 wall time    : 1s (sum over elements)

 ELEM PSEUDOPOTENTIAL                    STATUS    PARAMS      TRANSFER   ECUT/RHO     NOTE
 ----------------------------------------------------------------------------------------------------
 C    C.pbe-nc.UPF                       ok        std         -          -

 1 succeeded, 0 succeeded with warnings, 0 failed, 0 skipped (1 total)
```

## Reading that table

`STATUS ok`
: The engine ran, the file was written, and the structural checks on it passed.

`PARAMS std`
: Which variant of the recipe was used. PSlibrary ships several for some
  elements — `spn` for one with semicore, `n` for one without. Carbon has one,
  called `std`.

`TRANSFER -`
: **No transferability data.** Not a failure, and not a bad grade — no grade at
  all. The next section is about this.

`ECUT/RHO -`
: No cutoff scan was run. That needs `pw.x` and `--cutoff-scan`; it is off by
  default because it is much slower than the generation itself.

## Why the transferability column is empty

PseudoForge measures transferability by re-solving the atom in configurations
it was **not** fitted to, and comparing eigenvalues against the all-electron
answer. Those test configurations are not invented — they come from the
library's own test decks, because the library's authors chose configurations
that probe what matters for that element.

PSlibrary ships test decks for its PAW and ultrasoft sets. It ships none for
the norm-conserving set:

```bash
ls -d data/psl/tests/*/ | xargs -n1 basename
```

```text
paw-031 paw-alt paw-high paw-low paw-tot us-031 us-alt us-high us-low us-tot
```

There is no `nc`. So for a norm-conserving PSlibrary recipe there is nothing to
test against, and PseudoForge prints `-`.

!!! note "A dash is a claim about knowledge, not about quality"
    It would be easy to invent five configurations, run them, and print
    "excellent". That number would be about PseudoForge's guesses, not about
    the library's judgement of what carbon should be tested on. An empty column
    is the honest answer, and the report says which method produced any grade
    it *does* print, so two grades from different methods are never silently
    compared.

To get a transferability grade for carbon, ask for a family that has test
decks:

```bash
pseudoforge generate -e C -t paw -p psl-high -x pbe -o ./01-carbon-paw
```

```text
 C    C.pbe-n-kjpaw_psl.1.0.0.UPF        ok        n.1.0.0     excellent  -
```

## What was actually generated

Before running anything you can see the exact input deck:

```bash
pseudoforge recipe C -t nc -p psl-high -x pbe
```

```text
 &input
   title='C',
   zed=6,
   rel=1,
   config='[He] 2s2 2p2 3d-2',
   iswitch=3,
   dft='PBE'
 /
 &inputp
   pseudotype=2,
   file_pseudopw='C.pbe-nc.UPF',
   author='TM',
   lloc=0,
   tm=.true.
 /
2
2P  2  1  2.00  0.00  1.30  1.30  0.0
2S  1  0  2.00  0.00  1.30  1.30  0.0
```

This is PSlibrary's own deck, rendered with the functional and relativity you
asked for. Reading it top to bottom:

- `config='[He] 2s2 2p2 3d-2'` — the reference configuration. `[He]` is the
  frozen core. The `3d-2` is not a typo and not two electrons: a **negative
  occupation is `ld1.x`'s marker for an unoccupied channel**, included so the
  d scattering is described even though carbon has no d electrons.
- `iswitch=3` — generate, as opposed to `2`, which tests.
- `pseudotype=2` — norm-conserving, separable.
- `lloc=0` — the s channel is used as the local potential.
- `tm=.true.` — Troullier–Martins pseudisation.
- The two card lines are the channels being pseudised: `2P` and `2S`, both with
  a cutoff radius of 1.30 bohr.

`author='TM'` is upstream's own annotation, carried through verbatim.

## What you got

```bash
ls -R ./01-carbon
```

```text
./01-carbon:
PROVENANCE.txt  inputs  logs  manifest  pseudos  reports  state.tsv  tests

./01-carbon/pseudos:
C.pbe-nc.UPF  CITATION.txt  LICENSE.txt
```

`pseudos/` is the directory you copy into Quantum ESPRESSO's `pseudo_dir`. The
citation and licence files are in it deliberately, so the attribution travels
with the files instead of staying behind in the terminal.

`PROVENANCE.txt` records what made them:

```text
tool.name=PseudoForge
tool.version=1.3.0
engine.id=ld1
engine.label=Quantum ESPRESSO ld1.x
engine.version=v.7.6
engine.build=7de3694ef3fd
engine.binary=/opt/espresso/7.6/ld1.x
engine.upstream=https://gitlab.com/QEF/q-e
profile=psl-high
family=nc
functional=PBE
functional.requested=pbe
relativity=scalar
source=local
```

`functional=PBE` and `functional.requested=pbe` are both recorded because they
can differ — ask for r2SCAN from an engine with no meta-GGA path and the first
line says PBE while the second says r2scan. Here they agree. See
[Provenance](../architecture/provenance.md).

## Using it

```bash
cp ./01-carbon/pseudos/*.UPF $ESPRESSO_PSEUDO/
```

and in your `pw.x` input:

```text
ATOMIC_SPECIES
  C  12.011  C.pbe-nc.UPF
```

Norm-conserving carbon wants a high wavefunction cutoff — 60–80 Ry is a normal
starting point, with `ecutrho` at the default 4× ratio. To measure it rather
than guess:

```bash
pseudoforge generate -e C -t nc -p psl-high -x pbe --cutoff-scan -o ./01-carbon
```

which runs `pw.x` at a series of cutoffs and reports where the total energy
stops moving. That needs `pw.x` configured — see
[Installation](../getting-started/installation.md).

## The same run in the wizard

```bash
pseudoforge wizard
```

The screens, in order: **Formulation** → Norm-conserving. **Functional** →
PBE. **Relativity** → Scalar (the default). **Library** → PSlibrary 1.0.0 high
accuracy. **Elements** → type `C`. Then the review screen, which shows:

```text
  pseudoforge generate -e C -t nc -p psl-high -x pbe -j 4
```

That is the command at the top of this page. The wizard is a way of learning
the flags as much as a way of avoiding them.

---

Next: [Silicon and transferability](02-silicon.md) — a family with test decks,
and what the grades mean.
