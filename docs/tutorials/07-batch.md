# 7. A batch of the periodic table

Everything so far made one pseudopotential. Real work usually means a set: a
whole library for a project, or every element in a class of materials,
regenerated when you change functional.

This tutorial makes 29 of them, in 18 seconds, and then covers the three things
that matter about batches: what happens when one fails, what happens when you
interrupt it, and why the worker count cannot change the answer.

## What we are asking for

```bash
pseudoforge generate -e transition-metals -t paw -p psl-high -x pbe -j 8 -o ./07-batch
```

`-e transition-metals`
: A **selector** rather than a list. PseudoForge expands it against its own
  element table. Others include `all`, `lanthanides`, `actinides`,
  `main-group`, `magnetic`, `semiconductors`, and structured forms like
  `block:d`, `period:4`, `group:16`. Exclusions use `!`:
  `-e transition-metals,!Tc` drops technetium.

    Ranges are by **atomic number**: `1-18` is hydrogen through argon.
    `H-Ar` is not a range and is rejected. See [Elements and
    selectors](../reference/elements.md) for the full list.

`-j 8`
: Eight elements at a time. Each one is an independent atomic calculation, so
  this scales close to linearly until you run out of cores.

## What happens

```text
INFO  profile    PSlibrary 1.0.0 (high accuracy)  [generated]
INFO  family     PAW   functional PBE   Scalar-relativistic (no spin-orbit)
INFO  elements   29: Sc Ti V Cr Mn Fe Co Ni Cu Zn Y Zr Nb Mo Tc Ru Rh Pd Ag Cd Hf Ta W Re Os Ir Pt Au Hg
INFO  project    ./07-batch

== Generating ==
INFO  generating 29 element(s) with 8 parallel job(s)
OK    Sc  ->  Sc.pbe-spn-kjpaw_psl.1.0.0.UPF  (1s)
OK    Ti  ->  Ti.pbe-spn-kjpaw_psl.1.0.0.UPF  (1s)
OK    Mn  ->  Mn.pbe-spn-kjpaw_psl.1.0.0.UPF  (1s)
OK    V  ->  V.pbe-spn-kjpaw_psl.1.0.0.UPF  (1s)
...
```

The elements are listed before anything runs, which is the moment to notice
that a selector matched more, or less, than you meant.

Note that `Mn` finished before `V`. Completion order is whatever the scheduler
produces — but **the report is not in that order**, and neither is
`state.tsv`:

```text
 ELEM PSEUDOPOTENTIAL                    STATUS    PARAMS      TRANSFER   ECUT/RHO     NOTE
 ----------------------------------------------------------------------------------------------------
 Sc   Sc.pbe-spn-kjpaw_psl.1.0.0.UPF     ok        spn.1.0.0   good       -
 Ti   Ti.pbe-spn-kjpaw_psl.1.0.0.UPF     ok        spn.1.0.0   good       -
 V    V.pbe-spn-kjpaw_psl.1.0.0.UPF      ok        spn.1.0.0   good       -
 Cr   Cr.pbe-spn-kjpaw_psl.1.0.0.UPF     ok        spn.1.0.0   good       -
 ...

 29 succeeded, 0 succeeded with warnings, 0 failed, 0 skipped (29 total)

 TRANSFER measured by: ld1 iswitch=2
```

Results are ordered by atomic number, so the report reads like a periodic table
rather than like a race. Diffing two runs of the same batch is then meaningful.

## Failure isolation

One element failing does not stop the others, and does not affect their
results. When caesium failed a 52-element `psl-low` run, the other 51
completed, and the failure was recorded with its reason rather than as a bare
status:

```text
 FAILED ELEMENTS
   Cs   ERROR: implausible z_valence=-5.0000000000000000

 Logs for the failures are in ./psl-low-us/logs/.
```

The exit code is 1 if anything failed, **after** everything else has been
attempted. So in a script:

```bash
pseudoforge generate -e all -t paw -p psl-high -x pbe -j 16 -o ./lib || true
n=$(ls ./lib/pseudos/*.UPF | wc -l)
```

is a reasonable thing to write: you get everything that worked, and the
non-zero exit tells you to go and look at the report.

To see just the failures afterwards:

```bash
awk -F'\t' '$8 != "ok" && $8 != "ok-warn" { print $1, $11 }' ./07-batch/state.tsv
```

!!! note "That caesium failure was a real bug, and it is fixed"
    It was not a flaky run. Upstream PSlibrary's low-cutoff caesium recipe asks
    for `[Xe] 4f14`, which is 68 electrons in an atom with 55 of them, and
    `ld1.x` dutifully computed a negative valence charge and wrote the file
    anyway. The correction is declared in
    [`ERRATA.tsv`](../reference/errata.md), which is worth reading as a worked
    example of how a library's own recipe can be wrong.

## Resume

Run the same command again:

```bash
pseudoforge generate -e transition-metals -t paw -p psl-high -x pbe -j 8 -o ./07-batch
```

```text
INFO  Sc: already done (resume)
INFO  Ti: already done (resume)
...
```

Nothing is regenerated. An element is skipped when its state says `ok` **and**
its output file is actually on disk — deleting a file from `pseudos/` brings it
back into the queue, which is how you regenerate one element of a large set.

- `--no-resume` forces everything to be rebuilt.
- A **failed** element is always retried; only successes are skipped.

### Resume survives an interruption

Press Ctrl-C halfway through and run it again: the elements that finished
before the interrupt are still done.

This is worth stating because it was, for a while, not true. Each worker writes
its result to its own shard file, and those shards used to be merged into
`state.tsv` only when the batch *finished*. Killing a run left the shards on
disk and the state file empty, so a restart rebuilt everything it had already
done — 22 elements, in the run that found it. The merge now happens before
resume decides anything, and `tests/test_batch_isolation.sh` holds it there.

## Parallelism cannot change the answer

`ld1.x` writes scratch files with fixed names — `ld1.wfc`, `vx.pot` — into its
working directory. Eight workers sharing one directory would overwrite each
other's intermediates and produce results that depend on the race, silently.

Each element gets its own scratch directory, and the property is tested rather
than asserted: the same batch is run at `-j 1` and at `-j 8`, and **every
pseudopotential must be byte-identical**. It is.

That is also why `-j` is deliberately **not** stored in a saved
[recipe](../reference/recipes.md). A recipe holds what decides the output.
The worker count decides only how long you wait.

## Scaling up

```bash
# the whole table, as far as the library covers it
pseudoforge generate -e all -t paw -p psl-high -x pbe -j 16 -o ./psl-paw-pbe

# one class, excluding an element you do not want
pseudoforge generate -e lanthanides,!Pm -t paw -p psl-high -x pbe -j 8 -o ./lanth
```

A measured point of reference: 103 elements in 24 seconds at `-j 16` on a
desktop. Generation is cheap. What is not cheap is `--cutoff-scan`, which runs
`pw.x` several times per element; leave it off for a whole-table run and use it
on the handful of elements you actually care about.

## Saving the batch as a recipe

Having worked out a set of settings, keep them:

```bash
pseudoforge recipe save tm-paw-pbe -e transition-metals -t paw -p psl-high -x pbe
pseudoforge generate --recipe tm-paw-pbe -o ./07-batch-again
```

The recipe holds the physics and the element list, and reproduces the same
files byte for byte. It is plain text, and safe to send to a collaborator:

```bash
pseudoforge recipe export tm-paw-pbe tm-paw-pbe.recipe
```

See [Save and share a recipe](../how-to/write-a-recipe.md).

## What to do with the result

```bash
cp ./07-batch/pseudos/*.UPF $ESPRESSO_PSEUDO/
```

and keep `PROVENANCE.txt`, `manifest` and `reports/summary.csv` with your
project, not with the pseudopotentials. Six months later, `summary.csv` is what
tells you which of the three transition-metal libraries on your disk is the one
your published numbers came from.

---

That is the last tutorial. From here:

- [How-to](../how-to/choose-an-engine.md) for specific tasks
- [Reference](../reference/cli.md) for the flags and formats
- [Architecture](../architecture/overview.md) for how it is put together
