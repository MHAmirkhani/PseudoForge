# Changelog

The full changelog lives at the repository root, in
[`CHANGELOG.md`](https://github.com/MHAmirkhani/pseudoforge/blob/main/CHANGELOG.md).

It is written as a record of **what was wrong and how it was found**, not only
of what changed. Entries carry the measurement behind a claim, so a reader can
recheck it rather than take it on trust.

## What gets an entry

**Anything that changes what comes out.** A corrected recipe, a new auto-fix
strategy, a changed default, a functional mapping.

**Anything that was silently wrong.** The caesium recipe, the auto-fix that
never reached the provenance, the citation list that named four engines out of
nine. These get the most detail, because the interesting part is how they went
unnoticed.

**Anything a reader might otherwise mistake for a bug.** A refusal that is new,
a warning that is new, a file that now has a different name.

## What does not

Internal refactoring that cannot change behaviour, unless it was done to make a
class of bug impossible — in which case the class is the entry.

## The distinction that matters

!!! abstract "A physics change is never filed as a build fix."

A patch that touches a routine, a tolerance or a default **is a physics
change**, and the entry says so. A patch that moves an array off the stack so a
compiler will accept it is a build fix, and a test asserts that no decimal
number appears in it.

The caesium erratum is a physics-input change — it alters the all-electron
reference configuration a recipe is generated from — and the changelog says
that in those words, even though the corrected deck is bit-for-bit identical to
the obvious alternative.

## Versions

PseudoForge follows the repository's tags. The tool version is recorded in
every `PROVENANCE.txt`, so a result can be traced to the code that produced it
without depending on anyone's memory of when they ran it.

Zenodo mints a DOI for every release. `MD_DOI[pseudoforge]` is set to the
concept DOI from the first release after Zenodo integration, so every
citation PseudoForge prints resolves.
