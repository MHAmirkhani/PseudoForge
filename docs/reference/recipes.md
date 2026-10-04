# Recipe files

The format of a saved recipe. For how to use one, see
[Save and share a recipe](../how-to/write-a-recipe.md).

!!! note "Two senses of the word"
    A **library recipe** is one element's generation input within a profile —
    `pseudoforge recipe Fe` prints it. A **saved recipe**, this page, is your
    own settings kept by name. The subcommand tells them apart:
    `recipe <element>` prints a deck, `recipe save` stores a configuration, and
    no element symbol is spelled like a subcommand.

## Location

```bash
pseudoforge recipe path
```

`$RECIPE_DIR`, defaulting to `~/.pseudoforge/recipes/<name>.recipe`.

Names become file names, so they are restricted to letters, digits, `.`, `-`
and `_`. `../escape`, `/etc/passwd`, an empty name and anything with a space are
refused.

## The file

```text
# PseudoForge saved recipe
# Reload with: pseudoforge generate --recipe fe-paw-high
#
# This file is parsed, never sourced.  It cannot run commands.

pseudoforge.recipe=1
tool.version=1.3.0
saved=2026-09-17 00:31:02 +0330
description=magnetic 3d metals, project X
elements=Fe,Co,Ni

# specification
spec.engine=ld1
spec.family=paw
spec.formats=upf
spec.profile=psl-high
spec.rel=scalar
spec.source=local
spec.upf=2
spec.xc=pbe

# run options that change the result
run.tests=1
run.cutoff_scan=0
run.cutoffs=30 40 50 60 70 80 90 100
run.cutoff_tol=1.0
run.autofix=1
run.attempts=2
```

Plain `key=value`, readable and diffable.

## Keys

### Header

| Key | Meaning |
|---|---|
| `pseudoforge.recipe` | format version. **Required** — a file without it is not a recipe |
| `tool.version` | the PseudoForge that wrote it, for information |
| `saved` | timestamp, for information |
| `description` | free text, shown in `recipe list` |
| `elements` | comma-separated, already expanded from any selector |

### `spec.*`

One key per specification field. Every non-empty field is written, including
ones no command-line flag can set — the file is the authoritative
representation, and the command line is the readable one.

The complete list is whatever `SPEC` contains; `tests/test_recipe_roundtrip.sh`
fails if a field is added to `SPEC` and not accounted for.

### `run.*`

Options outside the specification that still change what comes out:

| Key | Flag |
|---|---|
| `run.tests` | `--test` / `--no-test` |
| `run.cutoff_scan` | `--cutoff-scan` |
| `run.cutoffs` | `--cutoffs` |
| `run.cutoff_tol` | `--cutoff-tol` |
| `run.autofix` | `--autofix` / `--no-autofix` |
| `run.attempts` | `--attempts` |

## What is deliberately not in one

**The output directory.** Where, not what.

**The worker count.** `-j 1` and `-j 8` produce byte-identical pseudopotentials
— `tests/test_batch_isolation.sh` asserts it — so storing `-j` would imply it
mattered.

## Versioning

`pseudoforge.recipe=1` is the format version. A recipe whose version is
**higher** than the reading PseudoForge understands is **refused**, not
half-read:

```text
ERROR <file> is format 99; this PseudoForge understands up to 1
```

Half-reading a newer format means dropping the keys that are new, which is
exactly the silent difference a recipe exists to prevent.

## Security

Recipes are meant to be shared, so a recipe from someone else is untrusted
input.

**Parsed, never sourced.** A `$(...)` or a backtick in a value is stored as the
literal text it is. A test writes a recipe containing a command substitution
and asserts nothing runs.

**Unknown keys are refused**, not ignored:

```text
ERROR <file> carries settings this version does not know: no_such_key
ERROR   refusing rather than generating something other than what it says
```

A silently dropped key is a recipe that generates something other than what it
says, which is worse than a file that will not load.

## Override rules

Flags given alongside `--recipe` win, wherever they appear on the command line.
The recipe is applied in a pre-pass before any other flag is parsed, so position
never changes meaning.

`-e` **replaces** the recipe's element list rather than appending to it.
Without a recipe, several `-e` on one line still accumulate.

## Round-trip guarantee

Save, reload, regenerate — and the pseudopotentials are byte-identical, input
decks included. `tests/test_recipe_roundtrip.sh` checks this against real
generation, not only against the file.
