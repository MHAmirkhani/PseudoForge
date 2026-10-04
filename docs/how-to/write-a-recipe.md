# Save and share a recipe

A recipe is a run's settings, kept by name and replayable. Saving one and
reloading it reproduces the same pseudopotentials **byte for byte**, input
decks included.

## Save

```bash
pseudoforge recipe save fe-paw-high -e Fe,Co,Ni -t paw -p psl-high -x pbe
```

```text
OK    saved fe-paw-high
INFO    ~/.pseudoforge/recipes/fe-paw-high.recipe
INFO    reuse with: pseudoforge generate --recipe fe-paw-high
```

Add a description for the listing:

```bash
pseudoforge recipe save fe-paw-high -e Fe,Co,Ni -t paw -p psl-high -x pbe \
    --description "magnetic 3d metals, project X"
```

## Use

```bash
pseudoforge generate --recipe fe-paw-high -o ./out
```

## Inspect, without running

```bash
pseudoforge recipe list
pseudoforge recipe load fe-paw-high      # the equivalent command line
pseudoforge recipe show fe-paw-high      # the file, plus the command
```

```text
INFO  equivalent command:
  pseudoforge generate -e Fe,Co,Ni --engine ld1 -t paw -p psl-high -r scalar --source local -x pbe -j 4
```

That is the same string the wizard's review screen prints, built by the same
code, so the two cannot disagree.

## Override

Flags given alongside `--recipe` win, **wherever they appear on the line**:

```bash
pseudoforge generate --recipe fe-paw-high -x pbesol -o ./out   # same set, PBEsol
pseudoforge generate -x pbesol --recipe fe-paw-high -o ./out   # identical
```

The recipe is applied in a pre-pass before any other flag is parsed, so
position never changes meaning.

!!! warning "`-e` replaces, it does not add"
    ```bash
    pseudoforge generate --recipe fe-paw-high -e Fe -o ./out    # Fe only
    ```

    An explicit `-e` **replaces** the recipe's element list. Appending would
    mean `-e Fe` generated Fe, Co and Ni, which is not "an explicit flag wins".

    Without a recipe, several `-e` on one line still accumulate as they always
    have.

## Share

Recipes are plain text and safe to send:

```bash
pseudoforge recipe export fe-paw-high fe-paw-high.recipe
pseudoforge recipe export fe-paw-high -            # to stdout
```

On the other side:

```bash
pseudoforge recipe import ./fe-paw-high.recipe
pseudoforge recipe import ./fe-paw-high.recipe local-name
pseudoforge generate --recipe fe-paw-high -o ./out
```

A recipe that will not load is not filed away as though it were usable —
`import` loads it first and refuses on failure.

!!! note "A recipe cannot run commands"
    Recipes are **parsed, never sourced**. A `$(...)` in a value is stored as
    the literal text it is. An unrecognised key is refused rather than skipped,
    because a silently dropped key is a recipe that generates something other
    than what it says. A recipe written by a newer PseudoForge than yours is
    refused rather than half-read.

    This matters because the whole point is to send them to people.

## What is in one

```bash
cat ~/.pseudoforge/recipes/fe-paw-high.recipe
```

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
run.autofix=1
run.attempts=2
```

A recipe holds **the physics and the element list** — everything that decides
what comes out.

Deliberately **not** in one:

- the **output directory** — where, not what;
- the **worker count** — `-j 1` and `-j 8` produce byte-identical files, so
  storing it would imply it mattered.

The full format specification is in [Recipe files](../reference/recipes.md).

## From the wizard

The review screen offers *Save these choices as a recipe*, and the main menu
offers *Start from a recipe saved earlier*. Both read and write the same files
as the command line, so a recipe saved in one appears in the other.

## For a paper

A recipe file and the run's `PROVENANCE.txt` together are a complete statement
of how the pseudopotentials were made: the recipe says what was asked for, the
provenance says what actually ran, down to the engine's build hash. Put the
recipe in the supplementary material.
