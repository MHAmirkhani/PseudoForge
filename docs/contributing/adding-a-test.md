# Adding a test

The rules this project's tests follow, and why each one exists.

## A suite states a property, then checks it

Every suite opens with a comment saying what property it defends and, where
there is one, the bug that made it necessary. That header is the most useful
part of the file six months later.

```bash
# ---------------------------------------------------------------------------
# Batch isolation.
#
# The property: a batch result does not depend on how many workers ran it,
# and one element's failure is confined to that element.
#
# When caesium failed a 52-element run, the first suspect was the batch rather
# than the recipe ... That turned out not to be the cause, but "we looked and
# it was fine" is not a property, and nothing was checking it.
# ---------------------------------------------------------------------------
```

## The house style

```bash
GREEN=$'\033[32m'; RED=$'\033[31m'; YELLOW=$'\033[33m'; DIM=$'\033[2m'; RESET=$'\033[0m'
pass=0 fail=0 skip=0
ok_()   { printf '  %sPASS%s  %s\n' "$GREEN" "$RESET" "$1"; pass=$((pass + 1)); }
bad_()  { printf '  %sFAIL%s  %s\n' "$RED" "$RESET" "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; fail=$((fail + 1)); }
skip_() { printf '  %sSKIP%s  %s\n' "$YELLOW" "$RESET" "$1"; skip=$((skip + 1)); }
```

`bad_` takes a **second argument**: what the failure means. `FAIL  the merge
still happens only at the end` is a fact; the second line — *"a restart after a
kill would redo work it had already finished"* — is why anyone should care.

End with the tally and `[ "$fail" -eq 0 ]`.

## Fixtures: real files, never invented ones

`tests/fixtures/` holds real engine output. A validator is tested by asserting
it **accepts a real file**, because the failure mode that actually happens is a
check written against an imagined format that rejects good data.

Three real examples, all caught this way:

- a search for `ghost` that matched the tool's own explanatory prose;
- a check for a `Vps.public` keyword that does not exist;
- a `.vps` file's opening banner of asterisks, flagged as an overflow marker.

**If a validator rejects a fixture, the validator is wrong.**

## Negative controls are not optional

A test that passes proves nothing until you have seen it fail for the right
reason.

```bash
# revert the recipe; the regression test must fail
sed -i "s/4f-1/4f14/" data/psl/us-low/Cs.spnl.1.0.0.tpl
bash tests/test_cs.sh          # expect: 3 failures
```

When a check is added, break the thing it checks and confirm it notices. If it
does not, the check is decoration.

The same applies to validators: accepting real files is half the job, and a
test must also show the check still bites on a truncated or corrupted one.

## Slow paths are gated, and the gate says what was measured

```bash
if [ "${PF_SLOW_TESTS:-0}" != 1 ]; then
    skip_ "generation gated behind PF_SLOW_TESTS=1 (measured: z_valence 9.0, transfer excellent, both families)"
```

The skip message carries the measurement, so someone reading a fast run still
learns what the slow path established.

```bash
PF_SLOW_TESTS=1 bash tests/test_cs.sh
```

## Tests may not need the network or an engine

The default suite runs against `tests/mock/`, which holds stand-in binaries.

A mock **validates its input and produces a plausible output**. `tests/mock/gnuplot`
parses the script it is handed, checks every data file it names exists, and
writes the PNG that script promised. A mock that ignored its input would let a
broken caller pass.

When a real engine is genuinely needed, gate it and skip cleanly:

```bash
elif [ ! -x "${LD1_BIN:-}" ] && ! command -v "${LD1_BIN:-ld1.x}" >/dev/null 2>&1; then
    skip_ "ld1.x not available (LD1_BIN=${LD1_BIN:-unset})"
```

!!! note "Load the rc file if you check for a binary"
    `LD1_BIN` comes from `~/.pseudoforgerc`. A test that checks for it after
    only `pf_config_defaults` is checking the bare default and will skip on a
    machine where the engine is present.

## Check the mechanism, not a proxy for it

Where a property is structural, assert against the real code:

```bash
grep -qE 'work=\$SCRATCH_DIR/\$\$-\$el' "$PF_LIB/run.sh" \
    && ok_ "run.sh gives each element a private scratch directory" \
    || bad_ "run.sh does not isolate the working directory" \
            "concurrent workers would share ld1.x's fixed-name scratch files"
```

and where it is behavioural, measure it:

```bash
# the same batch at -j 1 and -j 8 must be byte-identical
```

## Anti-drift checks

The strongest tests are the ones that fail when two things stop agreeing:

- every `SPEC` key maps to a flag or a declared exception — this is how
  `--rho0` surfaced, implemented and reachable from nothing;
- every generated reference table matches what the generator produces today;
- every command in the docs is a command the CLI parses;
- the recipe database differs from upstream **only** where `ERRATA.tsv` says.

These cost little and catch the class of bug nobody looks for.

## Wire it in

Name it `tests/test_<thing>.sh`, make it executable, and run everything:

```bash
for s in tests/test_*.sh tests/run_tests.sh; do bash "$s" || echo "FAILED: $s"; done
```

There is no central registry to update — the suites are discovered by glob.
