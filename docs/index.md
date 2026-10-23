# PseudoForge

**A pseudopotential generator that tells you what it did.**

PseudoForge drives nine atomic-structure codes from one command line. It
validates what they produce, converts between formats when that is honest and
refuses when it is not, and records in every output exactly which engine, which
version, which functional and which recipe produced the files — so that six
months later you can still answer the question.

---

## What it does

**Nine engines, one interface.** `ld1.x`, ONCVPSP, USPP, fhi98PP, OPIUM, GTH,
AtomPAW, APE and ADPACK. Each was written by the people who developed the
method it implements; PseudoForge drives them, and cites them.

**Ten layers, in order.** A pseudopotential is not one decision — it is the
formulation, functional, relativity, element selection, library profile,
source, engine, format, validation, and advanced settings. The guided interface
walks them in that order and the flags map onto them one for one.

**Four interfaces, one core.** The command-line interface (CLI), the
terminal user interface (TUI), the guided wizard, and the local HTTP API. No
module in `lib/` knows which one is calling it, which is why adding a fourth
was a rendering problem rather than a rewrite.

---

## Why it exists

Pseudopotentials are usually obtained in one of two ways: downloaded from a
library and trusted, or generated with a code whose input file you learned from
someone else's example.

Both work until you need something the library does not have — an unusual
valence partition, a core hole for XPS, a functional the library was not built
for — and then you are reading Fortran. And because every generator has its own
input format, its own conventions and its own idea of what a pseudopotential
file looks like, "try a different engine" is a day of work rather than a flag.

The practical consequence is visible in the literature: **a great deal of work
uses PBE pseudopotentials because PBE is what the convenient library had.**
That is a reasonable choice made for an unreasonable reason.

PseudoForge exists for the space between those two options. It ships the
published recipes so you can reproduce a library exactly, and it lets you
change one thing about them and see what happens — with the same validation
applied either way, and with the difference recorded rather than forgotten.

---

## One command

```bash
pseudoforge generate -e Si -t paw -p psl-high -x pbe -o ./out
```

```text
== Generating ==
OK    Si  ->  Si.pbe-n-kjpaw_psl.1.0.0.UPF  (1s)

== Transferability tests (ld1.x, iswitch=2) ==

 ELEM PSEUDOPOTENTIAL                    STATUS    PARAMS      TRANSFER   ECUT/RHO     NOTE
 ----------------------------------------------------------------------------------------------------
 Si   Si.pbe-n-kjpaw_psl.1.0.0.UPF       ok        n.1.0.0     excellent  -

 1 succeeded, 0 succeeded with warnings, 0 failed, 0 skipped (1 total)

 TRANSFER measured by: ld1 iswitch=2
```

That is a PAW dataset for silicon, generated from PSlibrary's own recipe,
re-solved in five configurations it was not fitted to, and graded. The method
that produced the grade is printed with it, because six engines can report a
transferability number and they do not all measure the same thing.

---

## Where to go next

<div class="grid cards" markdown>

-   :material-download:{ .lg .middle } **I want to install it**

    ---

    Requirements, Quantum ESPRESSO, building the engines, and what `doctor`
    tells you.

    [:octicons-arrow-right-24: Installation](getting-started/installation.md)

-   :material-play:{ .lg .middle } **I want to try it**

    ---

    From nothing to a validated pseudopotential in five minutes.

    [:octicons-arrow-right-24: Quick start](getting-started/quickstart.md)

-   :material-lightbulb:{ .lg .middle } **I want to understand it**

    ---

    The ten layers, the nine engines, the four interfaces, and what each
    choice costs.

    [:octicons-arrow-right-24: Concepts](getting-started/concepts.md)

</div>

Or follow a worked example: [seven tutorials](tutorials/index.md), from carbon
to a 29-element batch, each showing the output it actually produced.

For the reference pages: [Coverage](reference/coverage.md) lists which
profile covers which element, with what families and functionals;
[The native store](reference/store.md) is what ships and how it is
indexed; [Limitations](reference/limitations.md) is what it cannot do and
why; [Upstream](reference/upstream.md) is the defects it works around.

---

## What it will not do

This is on the front page rather than in a footnote, because it is the part
that decides whether the rest can be trusted.

**It will not convert a file into something it is not.** A GTH pseudopotential
is a dozen analytic coefficients; a UPF is a radial table. Turning one into the
other means constructing a new pseudopotential and labelling it with the
original's name. PseudoForge refuses, and says why —
[every refusal is documented](reference/formats.md).

**It will not silently substitute a functional.** Eight of the nine engines
have no meta-GGA code path. Ask one of them for r2SCAN and you get a PBE
dataset intended for use with r2SCAN — standard practice — and a note saying so
in the report and in the provenance. AtomPAW, which does implement r2SCAN, is
not given that note, because for AtomPAW it would be false.

**It will not claim a library's name for a file that library did not
produce.** The shipped recipes are byte-identical to PSlibrary's own inputs
except where [`ERRATA.tsv`](reference/errata.md) declares a correction — two
decks, both caesium, both recorded with the measurement behind them.

**It will not generate on the public server.** That runs on your machine, and
the website says so instead of queueing work nothing would collect.
[Why](architecture/http.md).

**It will not stamp a DOI it does not have.** The citation metadata carries no
DOI until one is minted.

---

## Licence and citation

GPL-2.0-or-later. Each engine carries its own licence, reproduced in
`LICENSE.txt` alongside any files it generates, together with the citation its
authors ask for.

```bash
pseudoforge citation --all
```

Generating a pseudopotential with an engine and publishing the result means
citing that engine's authors. PseudoForge writes the reference into the output
directory so that it travels with the files rather than staying behind in the
terminal.
