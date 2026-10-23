# Adding a format

Two different jobs, and it is worth knowing which one you are doing.

**A format an engine writes natively** — declare it, and the engine produces it
directly. No conversion, no caveat.

**A conversion between formats** — declare the path *and its cost*, and be
prepared to refuse.

## A native format

`data/formats.tsv`, one row:

```text
id      label           engines         extension   keyword     note
psp8    psp8 (ABINIT)   oncvpsp         psp8        -           ABINIT's native norm-conserving format.
```

| Column | Contents |
|---|---|
| `id` | what `--format` takes |
| `label` | the human name |
| `engines` | every engine that writes it **natively** — space-separated |
| `extension` | file extension, without the dot |
| `keyword` | the engine's own keyword for it, or `-` |
| `note` | one line: who reads this format |

The `engines` column is load-bearing. `--format` is validated against the
engine that will actually run, so a wrong entry here produces a confusing
refusal or — worse — a `psp8` file with UPF content.

That is the whole job. `tools/gen_reference.sh --write` picks it up, and the
[formats page](../reference/formats.md) regenerates.

## A conversion path

`pf_convert_load` in `lib/convert.sh`, keyed `<from>:<to>`:

```bash
CVT_TOOL[van:upf]=upfconv
CVT_KIND[van:upf]=exact
CVT_NOTE[van:upf]="Vanderbilt ultrasoft ASCII to UPF, by QE's upfconv.x."
CVT_ORDER+=("van:upf")
```

### Choosing the kind

**`exact`** — every number survives and a round trip returns the original. You
must be able to demonstrate the round trip, not assume it.

**`lossy`** — the conversion works and the target cannot hold everything. The
note must say **what is dropped**, in words that mean something without reading
the source. It becomes a warning, and that warning is written into
`PROVENANCE.txt` so it survives the terminal session.

**`refused`** — the target needs data the source does not contain.

### Writing a refusal

A refusal is a **reasoned answer**, not an error message. The note is shown
verbatim by `pseudoforge convert --why`, so it has to stand alone:

```text
A GTH file is a dozen analytic coefficients, not a radial table. QE's own
upfconv.x lists .gth as "DOES NOT WORK". Producing a UPF means sampling the
analytic form onto a grid, which is a construction rather than a conversion.
CP2K, CPMD and ABINIT read GTH directly.
```

Three things in there, and all three belong:

1. **why** the conversion cannot be a conversion;
2. **evidence** where there is any — here, upstream's own documentation;
3. **what to do instead.**

!!! abstract "The test for a refusal"
    Would producing a file mean **inventing data and then labelling the result
    with the source's name**? If so, refuse. That is the case for `gth → upf`,
    `vps → upf`, `pawxml → upf` and every cross-family conversion.

    These are not on a roadmap. What would be implemented is a new
    pseudopotential wearing an old one's name.

## Provenance is not optional

Every conversion writes `<output>.provenance`:

```text
source=Si.van
source_format=van
target_format=upf
tool=upfconv.x
tool_version=7.6
kind=exact
```

A `lossy` conversion records what was lost. If your path cannot produce this,
it is not finished.

## External tools

A conversion may shell out — `upfconv.x` does — but the tool is found on `PATH`
or via a configured variable, **never bundled**. Register it so its absence is
reported rather than hidden, and record its version in the provenance, because
a conversion's behaviour is a property of the tool that did it.

### Check that the tool exists before you register the path

Three paths in this tree were registered as **exact**, performed by ABINIT's
`pspconvert`. There is no such program. It was not a typo and not a version
skew: it is absent from the ABINIT 8.10.3 and 9.10.3 source trees and from the
conda-forge binaries of 8.10.2 and 10.0.3, and `abitk` has no pseudopotential
subcommand. The registry promised a conversion that could never run, and the
report's `AVAILABLE: no` column read as *install ABINIT and it will work*.

Two things follow, and both are enforced by `tests/test_convert.sh`:

1. **Prove "exact" with physics, not with validation.** Run the path on a
   real file, then give the source and the result to a code that reads both
   and compare an energy. Validation checks form: a converted `.van` passed it
   while being a file `pw.x` refused to open. `tests/test_convert.sh` does
   this with `pw.x` for every exact path. And read the tool's source, not its
   help — `upfconv -h` lists `.cpi` and `.cpmd`, and its code reads neither.
2. **Refuse in the right category.** `CVT_REFUSAL` is `physics` when the
   target needs numbers the source does not contain, and `no-tool` when the
   conversion is possible and nobody wrote it. Collapsing the two loses the
   only part a reader can act on.

### Two traps that have already been paid for

`upfconv.x` **exits 0 on failure**, and it names its output `.UPF2` rather than
what you asked for. Both are handled, and both are pinned by tests, because
both were discovered the hard way.

## Test it

```bash
bash tests/test_convert.sh
```

A new path needs:

- a **real fixture** in `tests/fixtures/`, converted and checked — never an
  invented file;
- for `exact`: a demonstrated round trip;
- for `lossy`: a check that the warning is produced **and reaches the
  provenance**;
- for `refused`: a check that it refuses, and that `--why` explains it;
- the generated formats table regenerated (`tools/gen_reference.sh --write`).

See [Adding a test](adding-a-test.md) for the fixture rule, which matters here
as much as anywhere.
