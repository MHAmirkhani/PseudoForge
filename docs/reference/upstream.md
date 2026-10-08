# Upstream

A record of the defects PseudoForge works around, what was reported
upstream, what was not, and how to tell whether a local fix is still
needed. The distinction matters because a local patch that is never
re-examined becomes a fork.

## The policy

PseudoForge patches an upstream source tree only when all three hold:

1. The defect prevents a pseudopotential from being produced at all
   (not merely produces one that is less accurate).
2. There is no local workaround -- no flag, no build option, no
   alternative engine -- that produces the same result.
3. The fix is small enough to state in a paragraph and to verify in a
   test.

If any of the three fails, the limitation is documented in
[Limitations](limitations.md) and the engine is left as it ships. A
documented limitation is honest; a silent fork is not.

## Reported

### OPIUM: six writers crash on d-shell elements

**What is broken.** Six of OPIUM 4.1.0's ten output writers (`fhi`, `ncpp`,
`cpmd`, `casino`, `champ`, `siesta`) build the
scratch-file name for each angular-momentum channel from the loop index
rather than from the real `aorb_.lo[i]`. On any element whose
valence shells are not contiguous -- every 3d and 5d transition metal --
the writer dereferences a filename that was never created and the engine
dies with SIGSEGV before writing anything.

**Reported.**

- [rappegroup/opium#1](https://github.com/rappegroup/opium/issues/1) -- the issue
- [rappegroup/opium#2](https://github.com/rappegroup/opium/pull/2) -- the pull request

Both are open at the time of writing. The fork is at
[MHAmirkhani/opium, branch `fix/dshell-scratch-filenames`](https://github.com/MHAmirkhani/opium/tree/fix/dshell-scratch-filenames),
commit `a30a90c`.

**Fixed locally.** PseudoForge applies the fix to the working copy of the
OPIUM source tree at build time, between `build_prepare_src` and
`configure` / `make`. The upstream tree on disk is untouched.
The patch lives at `lib/patches/opium/`:

```text
lib/patches/opium/
  apply.sh                       applies it, idempotently
  README.md                      why it exists, what it does
  0001-dshell-writers.patch      the fix itself
```

The apply script detects the corrected form and skips those files, so
when upstream merges the local patch becomes a no-op rather than a
conflict.

**Effect.** With the patch, OPIUM's ten writers all run on the full
element table. The store went from 297 files to 1,945 for OPIUM alone.
Before the fix, requesting `--format fhi` on iron produced an engine
crash; after it, a file.

**How to tell if the patch is still needed.** After a rebuild, run:

```bash
cd "$PF_SRC_DIR/opium"
grep -n 'aorb_\.lo\[i\]' src/*.f90 | head
```

If the writers reference `aorb_.lo[i]` the fix is present (either from the
patch or from upstream) and the local one is redundant. The issue will
be closed when the PR is merged; until then, the local patch is what
makes `opium` work at all on transition metals.

## Not reported

Two defects are documented but not filed upstream. In both cases the
reason is the same: it is not clear the maintainer would regard the
behaviour as a bug, and filing a report that starts an argument is worse
than documenting the behaviour and letting a user decide.

### AtomPAW: `type="LDA"` on meta-GGA output

AtomPAW 4.2.0.6 writes the functional into its PAW-XML header as:

```xml
<xc_functional type="LDA" name="MGGA-R2SCAN-001"/>
```

The `type` attribute says LDA on a meta-GGA dataset. Only `name` is
correct. A consumer that reads `type` -- the obvious thing to read,
and what the attribute is for -- will treat an r2SCAN dataset as LDA.

**Not reported.** The writer has other limitations on the meta-GGA path
that suggest the attribute is not the maintainer's priority, and the
workaround is one line in the reader. PseudoForge checks for the
combination and warns, and the warning reaches the run's
`PROVENANCE.txt`. See
[the AtomPAW page](engines/atompaw.md#upstream-defect-typelda-on-meta-gga-output).

### APE: GGA path fails for open-d transition metals

APE's `-x pbe` run fails for Ti, Fe, Cu, Zn, Ag: the occupied d
shell is driven unbound during the SCF. APE's own shipped chromium test
fails the same way when only the functional is changed, so the defect
reproduces without PseudoForge in the loop.

**Not reported.** The cause is not established, and a report that says
"it does not converge" without a diagnosis is not useful to a
maintainer. The limitation is documented in
[the APE page](engines/ape.md) and in [Limitations](limitations.md).
If you use APE and hit it, the diagnosis would be welcome -- open an
issue on the [PseudoForge repository](https://github.com/MHAmirkhani/pseudoforge)
with the failing input and the engine's own log.

## Fixed locally without a report

### --projector on non-ld1 engines

Before this was fixed, `--projector` was accepted by every engine,
applied by `ld1` only, and stamped `-xp` into the file name of
the rest. The file with `-xp` in its name did not contain a second
projector: the deck it came from was byte-for-byte the one without the
flag.

This is not an upstream bug. Every other engine was doing exactly what
it was asked: build a deck in its own format, which does not have a
place for an extra projector. The bug was in PseudoForge accepting the
flag and promising a change it did not make. `--projector` is now
refused on every engine except `ld1`, before anything runs. See
[Limitations](limitations.md#-projector).

### --rcut-scale on engines that ignore it

The same class of bug. `--rcut-scale` was accepted everywhere,
applied by `ld1`, `oncvpsp`, `opium` and `ape`, and stamped
`-rc<f>` into the file name of the rest. It is now refused elsewhere
with a message that says which engines do support it.

## A note on what does not belong here

Two categories of thing look like upstream defects and are not, and the
difference is worth writing down because it comes up.

**A format that cannot represent something** is a property of the
format, not a bug in the writer that refuses it. UPF has no field for
the kinetic-energy density, so AtomPAW's UPF writer refuses a meta-GGA
dataset -- correctly. QE 7.x's `ld1.x` does not write UPF v1, so
`--upf 1` is refused -- correctly. Neither is a defect to report.

**A functional that is approximated by a proxy** is not a mislabelled
file. A PBE pseudopotential asked for as r2SCAN is a PBE
pseudopotential; the file says PBE, the provenance says
`functional.requested=r2scan`, and both are true. See
[Choose a functional](../how-to/choose-a-functional.md).
