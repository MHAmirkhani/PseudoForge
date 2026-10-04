# 6. Meta-GGA with AtomPAW

This tutorial is the one where PseudoForge tells you *no*, and the reason is
worth more than the pseudopotential.

Meta-GGA functionals — SCAN, r2SCAN, TPSS — use the kinetic-energy density as
well as the density and its gradient. They are substantially better than GGA
for a range of solids. Almost no atomic code implements them. What everyone
does in practice, and what the literature is built on, is to run SCAN
calculations on GGA-generated pseudopotentials.

AtomPAW is the exception, and this tutorial uses it. But first, the refusal.

## Start by asking for the obvious thing

```bash
# expect: refused
pseudoforge generate -e Si -t paw -p atompaw -x r2scan -o ./06-scan
```

```text
ERROR AtomPAW cannot generate meta-GGA with a relativistic solver.
  Its r2SCAN path is non-relativistic only.
  Re-run with -r nonrel, or choose a GGA functional to keep scalar relativity.
```

Nothing was generated.

AtomPAW's meta-GGA implementation does not cover the relativistic solver. Run
it that way directly and it gets through the first SCF cycle and stops with
`for relativistic solver -- error stop`, which reaches you, after the harness
has interpreted what it can, as `no convergence in boundsr` — a message that
tells you nothing about what to do.

!!! question "Why not just switch to non-relativistic automatically?"
    Because relativity is physics, not a build setting. Scalar-relativistic and
    non-relativistic silicon are different reference atoms, and a tool that
    quietly gave you the second when you asked for the first would be lying by
    omission in a way you would not discover until your results disagreed with
    someone else's.

    PseudoForge refuses, names the constraint, and tells you both ways out. The
    choice stays yours.

## The run that works

```bash
pseudoforge generate -e Si -t paw -p atompaw -x r2scan -r nonrel -o ./06-scan
```

```text
WARN  r2SCAN (metaGGA) -- generated natively by AtomPAW (Holzwarth)

== PseudoForge 1.3.0 ==
INFO  profile    AtomPAW (Holzwarth)  [reproducible]
INFO  family     PAW   functional R2SCAN   Non-relativistic
INFO  elements   1: Si

== Generating ==
INFO  generating 1 element(s) with 4 parallel job(s)
WARN  Si  ->  Si.r2scan-atompaw.xml  -- AtomPAW writes no UPF for meta-GGA: the
      kinetic-energy density has no place in that format. This is a PAW-XML data
      set, read by ABINIT and by any code that takes PAW-XML.;
      WARNING: this file says xc_functional type="LDA" but name="MGGA-R2SCAN-001".

== Transferability tests (atompaw leakage/overlap) ==
```

`functional R2SCAN`, not `PBE`. This one really is r2SCAN. You can see it in
the deck AtomPAW was given:

```bash
head -2 ./06-scan/inputs/Si.atompaw.input
```

```text
Si 14
MGGA-R2SCAN-001 nonrelativistic loggridv4 2001
```

## How that differs from every other engine

Ask any of the other eight for r2SCAN:

```bash
pseudoforge generate -e Si -t paw -p psl-high -x r2scan -o ./06-scan-proxy
```

```text
 NOTE ON THE FUNCTIONAL
   r2SCAN (metaGGA) -- Quantum ESPRESSO ld1.x cannot generate this family;
   generated with Perdew-Burke-Ernzerhof instead. As SCAN; r2SCAN is the
   numerically better behaved variant.
   The UPF files carry dft=PBE. Use them with R2SCAN in pw.x; that is
   standard practice, but the pseudopotential was not generated
   self-consistently with R2SCAN.
```

That note is accurate, it is in the report and in `PROVENANCE.txt`, and the
file honestly carries `dft=PBE` rather than claiming to be something it is not.
This is the normal, accepted workflow — it is what the SCAN literature does.

The AtomPAW run does **not** get that note, because for AtomPAW it would be
false. The check is engine-aware: it asks whether the functional that will
actually be used differs from the one you requested, not whether the registry
calls meta-GGA a proxy in general.

!!! note "An earlier version got this wrong"
    The note used to key off the functional registry alone, so an AtomPAW
    r2SCAN run printed "generated natively by AtomPAW" and then, two lines
    later, "was not generated self-consistently with R2SCAN". Both sentences
    cannot be true. It now asks the question it means.

## Two warnings, and what to do about each

### `AtomPAW writes no UPF for meta-GGA`

The output is `Si.r2scan-atompaw.xml`, not a `.UPF`. That is not a limitation
of PseudoForge and it is not something to work around:

> UPF has no tag for the kinetic-energy density. For a meta-GGA data set that
> term is what makes it meta-GGA, so the conversion would return an r2SCAN file
> that is no longer r2SCAN.

So the conversion `pawxml` → `upf` is **refused**, not merely unimplemented.
The file you have is PAW-XML, read by ABINIT and by any code that accepts
PAW-XML. If you need UPF, you need a GGA dataset — which is the proxy route
above, and which is a legitimate choice, not a defeat.

```bash
pseudoforge convert --why pawxml upf
```

prints that reasoning on demand. See [Formats and
conversions](../reference/formats.md).

### `this file says xc_functional type="LDA" but name="MGGA-R2SCAN-001"`

This is a **defect in AtomPAW's PAW-XML writer**, not in your data. AtomPAW
writes the functional's *name* correctly and the functional's *type* attribute
as `LDA` regardless. The numbers in the file were computed with r2SCAN; the
label is wrong.

PseudoForge detects this and says so rather than passing a mislabelled file
along silently. What to do depends on the reader:

- Codes that dispatch on `name` read it correctly and you can ignore this.
- Codes that dispatch on `type` will treat it as LDA. Fix the attribute by hand
  before use, or use a reader that keys on the name.

The warning survives into `PROVENANCE.txt`, so whoever picks the file up in six
months finds out too.

## What "transferability" means here

```text
== Transferability tests (atompaw leakage/overlap) ==
```

A third measurement, different again from `ld1 iswitch=2` and from ONCVPSP's
configuration tests. AtomPAW reports logarithmic-derivative agreement and
charge leakage outside the augmentation sphere. It is a real diagnostic; it is
not on the same scale as a maximum eigenvalue error in Ry, and PseudoForge does
not pretend otherwise. The method is printed with the result, every time.

## The provenance

```text
engine.id=atompaw
engine.label=AtomPAW (Holzwarth)
engine.version=4.2.0.6-git914acde
engine.build=abe832a1ea52
profile=atompaw
family=paw
functional=R2SCAN
functional.requested=r2scan
relativity=nonrel
```

`functional=R2SCAN` and `functional.requested=r2scan` **agree**. In the proxy
run above, the first would say `PBE` and the second `r2scan`. Those two lines
exist precisely so that this distinction survives in the file rather than in
someone's memory of which run was which.

## Which route should you take?

| | AtomPAW meta-GGA | GGA dataset used with meta-GGA |
|---|---|---|
| Functional in the dataset | really r2SCAN | PBE |
| Relativity | non-relativistic only | anything |
| Output format | PAW-XML | UPF |
| Works with `pw.x` | not directly | yes |
| Matches the literature | less common | this is what most papers did |

For most people, most of the time, the second row is the answer: generate with
PBE, run with r2SCAN, and say so in your methods section. Use the AtomPAW route
when you specifically want a self-consistently generated meta-GGA dataset and
your code reads PAW-XML.

Either way, PseudoForge writes down which one you did.

---

Next: [A batch of the periodic table](07-batch.md) — 29 elements, parallelism,
resume, and what happens when one of them fails.
