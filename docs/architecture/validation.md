# Validation

What PseudoForge checks, how, and why the grades carry their method with them.

For the practical side, see [Validate a
pseudopotential](../how-to/validate.md).

## Three checks, three questions

| Check | Question | When |
|---|---|---|
| structural | is the file well formed and physically plausible? | always |
| transferability | is it right for atoms it was not fitted to? | when the library ships test decks |
| cutoff scan | how expensive is it? | on `--cutoff-scan` |

## Structural

Runs on every generated file and on `pseudoforge validate`. It reads the file
and checks internal consistency: the header parses, `z_valence` is positive and
plausible for the element, the grid is monotonic, the projector count matches
the declared `l_max`, the augmentation block is present if the file claims to
be ultrasoft or PAW.

This exists because **the engines do not do it**. `ld1.x` will compute a
valence charge of −5, write the UPF, and exit 0. Nothing in the engine objects.

```text
ERROR: implausible z_valence=-5.0000000000000000
```

That message is the whole reason this layer exists.

## Transferability, and why the method travels

A pseudopotential is fitted to one reference configuration. The question that
matters is whether it stays correct elsewhere.

Six engines can answer it, and **they do not all measure the same thing**:

| Method | What it measures |
|---|---|
| `ld1 iswitch=2` | re-solves the atom in the library's unfitted configurations, compares eigenvalues against all-electron |
| ONCVPSP's own tests | the configuration tests ONCVPSP runs internally |
| `atompaw leakage/overlap` | log-derivative agreement and charge leakage outside the augmentation sphere |
| OPIUM design diagnostics | the design-quality figures OPIUM reports |

So every verdict is recorded with the method that produced it:

```text
Si	Si.pbesol-...UPF	0.000640	0.000171	excellent	ld1 iswitch=2	re-solved in unfitted configurations
```

and the report repeats it in the footer:

```text
 TRANSFER measured by: ld1 iswitch=2
```

An `excellent` from one method and a `good` from another are not comparable,
and a table that omitted the method would invite exactly that comparison.

### The scale

One function, `transfer_verdict` in `lib/validate.sh`, grades every engine's
number:

| Grade | Largest eigenvalue error |
|---|---|
| `excellent` | below 1 mRy |
| `good` | below 5 mRy |
| `marginal` | below 20 mRy |
| `poor` | 20 mRy or more |
| `no-data` | the test ran and produced no usable number |
| `-` | no test deck exists for this set |

Thresholds live in one place so six engines cannot drift into grading
differently.

### An empty column is a claim about knowledge

The test configurations come from the **library's own** test decks, because the
library's authors chose configurations that probe what matters for that
element. PSlibrary ships them for its PAW and ultrasoft sets and not for
norm-conserving.

So a norm-conserving PSlibrary run reports `-`. Inventing five configurations
and grading against those would produce a number about PseudoForge's guesses
rather than the library's judgement.

## Ghost states

A spurious bound state introduced by the separable Kleinman–Bylander form — an
eigenvalue the real atom does not have.

**Where it is decides what it means.** Below or near the valence energies it is
fatal. Tens of Ry above, it is common in published tables — including SG15's
own files — and PseudoForge labels it informational rather than failing the
run:

```text
positive-energy ghost above ~39.13 Ry (informational; common in published tables)
```

Recorded, never hidden, and never treated as equivalent to a ghost that
matters.

## Failure isolation

One element failing must not affect the others, and does not:

- each element runs in **its own scratch directory**, because `ld1.x` writes
  fixed-name scratch files (`ld1.wfc`, `vx.pot`) and workers sharing a
  directory would overwrite each other's intermediates silently;
- each worker writes its result to **its own state shard**, merged by the
  parent, rather than appending to a shared file;
- the batch exit code is non-zero if anything failed, **after** everything else
  has been attempted;
- results are ordered by atomic number in the report, so completion order never
  leaks into the output.

The strong form of this is tested rather than asserted: the same batch is run
at `-j 1` and `-j 8`, and every pseudopotential must be **byte-identical**.

## Resume

An element is skipped when its state says `ok` **and** its output file is on
disk. Deleting a file brings it back into the queue. A failed element is always
retried.

Shards are merged **before** resume decides anything. They used to be merged
only when a batch finished, so killing a run left the shards on disk and the
state file empty, and a restart rebuilt everything it had already done — 22
elements, in the run that found it.

## Validators must be written against real files

The rule, because it has been broken three times, always the same way — a check
that looked reasonable, was written against an imagined format, and rejected
good data:

- searching for `ghost` in `pslp` output matched the tool's own prose,
  *"the ghost state analysis will assume a zero reference energy"*;
- a check for a `Vps.public` keyword that does not exist in the OpenMX format
  rejected every file ADPACK produces;
- the banner of asterisks a `.vps` opens with was flagged as a Fortran overflow
  marker.

**A validator that rejects valid output is worse than no validator**: it turns
a working engine into a mysterious failure.

The practices that follow are in [Adding an
engine](../contributing/adding-an-engine.md).

## What none of this tells you

Whether the pseudopotential is right for **your** system. Converge the cutoff
on your actual structure, reproduce a known property, and only then trust it
for the property you want. PseudoForge gets you to the point where that is
worth starting.
