# Adding an engine

Ten steps, and step 8 is the one people get wrong.

See [The engine interface](../architecture/engine-interface.md) for the
contract this implements.

## 1. Register it

`lib/engines.sh`:

```bash
ENG_LABEL[newengine]="New Engine (Author)"
ENG_FAMILIES[newengine]="nc"
ENG_BIN_VAR[newengine]=NEWENGINE_BIN
ENG_BINARIES[newengine]="newengine.x"
ENG_SRC[newengine]="https://example.org/newengine-1.0.tar.gz"
ENG_UPSTREAM[newengine]="https://example.org/newengine"
ENG_LICENSE[newengine]="GPL-2.0-or-later"
ENG_NATIVE_UPF[newengine]=no
ENG_NOTE[newengine]="one line on what it is for"
```

The registry is the list. Everything that enumerates engines reads it, so this
step alone gets the engine into the help text, `doctor`, the citation list and
the generated reference page.

## 2. Build recipe

In `lib/build.sh`. Fetch, verify, patch if needed, compile into
`$(eng_prefix)`, and record a build id.

!!! danger "A build fix may not change physics"
    No routine, tolerance, default or input deck may be modified. If a patch
    has to touch one, it is a physics change and must be documented as one.

    ADPACK's patch moves 9 MB of arrays off the stack using pointer-to-array
    types, so every existing subscript is untouched — and a test asserts no
    decimal number appears in the patch.

Common legacy-Fortran flags, in case they save you an afternoon:
`-fno-automatic`, `-std=legacy`, `-fallow-argument-mismatch`, `-fcommon`; and
strict `-std=c99` for C.

## 3. Declare its formats

`data/formats.tsv` — add the engine to the `engines` column of every format it
writes natively.

## 4. Build the deck

`ib_build_<engine>` in `lib/input_builder.sh`. Turn `SPEC` into the engine's
input format.

!!! warning "The heredoc trap"
    Writing a deck through a heredoc that contains `\n` inside an `awk printf`
    has broken this project roughly six times. The `\n` becomes a real newline
    and `awk` dies with `unterminated string`.

    `ib_check_deck` and `tests/test_decks.sh` exist to catch it. Run them.

## 5. Map the functionals

`ib_<engine>_xc`. Return non-zero for a functional the engine cannot generate
itself; the proxy machinery takes it from there.

If the engine *can* do meta-GGA, add it to `xc_engine_native` in `lib/xc.sh` so
a user is not told their dataset is a proxy when it is not.

## 6. Execute it

`exec_<engine>` in `lib/executor.sh`. Run in the per-element scratch directory,
with a timeout, capturing the log.

Never `read`. Never write to the terminal. See [the sink
contract](../architecture/sink-contract.md).

## 7. Diagnose failures

Extend `ld1_diagnose`-style classification if the engine's errors have
structure worth reading, and add strategies to `autofix_strategy`.

Strategies fire **on a signature**, never as a rule. A blanket rule changes the
answer for every element that did not need it.

## 8. Write the validator — against a real file

**Read a real output file first. Never invent a keyword.**

This is written down because it has been broken three times, always the same
way — a check that looked reasonable, was written against an imagined format,
and rejected good data:

- searching for `ghost` in `pslp` output matched the tool's own explanatory
  prose, *"the ghost state analysis will assume a zero reference energy"*, and
  reported a ghost in a clean pseudopotential;
- `vps_validate` looked for a `Vps.public` keyword that does not exist in the
  OpenMX format, and rejected every file ADPACK produces;
- the same function flagged the banner of asterisks a `.vps` opens with as a
  Fortran overflow marker.

**A validator that rejects valid output is worse than no validator**: it turns a
working engine into a mysterious failure.

Three practices follow:

1. **Put a real file in `tests/fixtures/`** and assert the validator accepts
   it. If a validator rejects a fixture, the validator is wrong.
2. **Match delimiters, not words.** `Pseudo.Potentials` appears in a comment
   banner and inside a different keyword in the same file; only
   `<Pseudo.Potentials` is the data block. That was found by a fixture test,
   not by reading.
3. **Check corruption separately.** Accepting real files is half the job; a
   test must also show the check still bites on a truncated or overflowed one.

## 9. Cite it

!!! abstract "Before you merge an engine, find its citation. Check the tarball. If there isn't one, say so explicitly."

Look, in this order, in the source tree you just built from:

```bash
ls  <tree>/{CITATION*,README*,AUTHORS,COPYING,LICEN[SC]E*}
ls  <tree>/doc <tree>/docs
grep -ril 'please cite\|how to cite\|should cite' <tree>
```

Authors put it in surprising places. APE has a **"How to cite APE"** heading in
`README.md`; GTH puts a `Please cite:` block **inside every data file it
generates**. Neither is where you would look first.

### If you find one

Record it *and where it came from*:

```bash
MD_CITATION[newengine]="A. Author, \"Title\", Journal 12, 345 (2020)."
MD_DOI[newengine]="10.xxxx/yyyy"
MD_VERIFIED[newengine]=yes
MD_CITE_SOURCE[newengine]="the \"How to cite\" section of README.md in the source tree"
MD_ALSO_CITE[newengine]="other-id"          # ids, not prose
```

`MD_CITE_SOURCE` is what lets the next person recheck the claim without
repeating your search. `MD_ALSO_CITE` holds **ids of other entries**, which
`md_citation` resolves — a distribution that asks for three papers gets three.

Check whether the reference is already in the file under another id. GTH's was:
it had been verified under the `cp2k-gth` profile id for months, and the engine
id simply had no entry, so `pseudoforge citation` reported "Unverified" for a
citation the codebase already held. Alias it, the way `ld1` aliases
`quantum-espresso`.

### If you do not find one

Leave it unverified, and say **specifically** what you looked at and what the
next person should check:

```bash
MD_VERIFIED[newengine]=no
MD_CITE_TODO[newengine]="Check https://example.org/newengine/docs -- the
tarball ships only source/ and work/, with no README and no doc/."
```

A TODO that names a file or a page is a checklist item. A bare `Unverified` is
a mystery, and mysteries do not get resolved.

**Never copy a citation from a secondary source** — not from a wiki, not from
another paper's bibliography, not from memory. A wrong reference propagates,
and it propagates with your name on it.

## 10. Test it

At minimum:

- capability queries return the right answers;
- a deck is built correctly for a representative element;
- the validator accepts a real fixture and rejects a corrupted one;
- the engine appears in `doctor`, in `pseudoforge citation --all`, and in the
  generated engines table.

```bash
bash tests/test_engines.sh
bash tests/test_decks.sh
bash tests/test_docs.sh          # the generated table must be regenerated
tools/gen_reference.sh --write
```

See [Adding a test](adding-a-test.md).
