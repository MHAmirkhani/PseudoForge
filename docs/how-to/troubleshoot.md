# Troubleshoot a failure

What PseudoForge tries on your behalf, in what order, and what to do when it
runs out of ideas.

## First: read the note

Every failure is recorded with a reason, in three places:

```bash
# the report
grep -A3 'FAILED ELEMENTS' ./out/reports/summary.txt

# the state file, column 11
awk -F'\t' '$8 != "ok" && $8 != "ok-warn" { print $1, $11 }' ./out/state.tsv

# the engine's own log, unedited
less ./out/logs/Cs.log
```

The log is the engine's raw output. PseudoForge never rewrites it, so if the
summary and the log disagree, believe the log and
[report it](https://github.com/MHAmirkhani/pseudoforge).

## The auto-fix engine

When an engine fails, PseudoForge reads the log, classifies the failure, and
retries with a changed parameter — up to `AUTOFIX_MAX_ATTEMPTS` times
(default 2). Every retry is reported as it happens and recorded in the
provenance:

```text
WARN  Cu: chi -> retry 1/2: widen all cut-off radii by 5%
WARN  Cu: chi -> retry 2/2: widen all cut-off radii by 12% and soften the local channel
OK    Cu  ->  Cu.pbe-spn-kjpaw_psl.1.0.0-ch1s.UPF  (2s)
```

```bash
grep autofix ./out/PROVENANCE.txt
```

```text
autofix.Cu=widen all cut-off radii by 12% and soften the local channel
```

!!! warning "An auto-fix is a physics change"
    Widening a cutoff radius produces a *different, softer* pseudopotential.
    That is why the fix is named in the report, in the note column, in the
    provenance, and — when a library recipe was modified — in the file name
    itself via a tag like `-rc1p12`. Turn it off with `--no-autofix` when you
    want to see the unmodified failure.

### What it classifies, and what it tries

The classification comes from the engine's own error, not from guesswork:

| Cause | Detected from | Attempt 1 | Attempt 2 |
|---|---|---|---|
| `chi` | `compute_chi`, `nodenum` | widen all rc by 5% | widen by 12%, soften the local channel |
| `augmentation` | `find_qi`, `compute_q*` | switch augmentation to Bessel | `PSQ` with `rmatch_augfun=0.9` |
| `scf` | `ascheq`, `lschps`, "convergence not achieved" | damp mixing (`beta=0.1`) | `beta=0.05`, `tr2=1.0d-13` |
| `grid` | `do_mesh`, `import_upf` | `rmax=120` | `rmax=150`, `dx=0.008` |
| `local` | `pseudovloc`, `set_psi_in` | local from the AE potential, `rcloc=1.2` | use `l=0` as local |
| `paw` | any `*paw*` routine | `PSQ` augmentation, NC matching | widen rc by 8% |
| `occupation` | "wrong occupations" | fall back to the tabulated ground state | — |
| `timeout` | killed by `LD1_TIMEOUT` | damp mixing | — |
| `unknown` | anything else | widen rc by 5% | — |
| `valence` | "supplied … and calculated … valence" | **not retried** | — |

### Why `valence` is not retried

A disagreement between the valence charge you supplied and the one the
configuration implies is arithmetic, not convergence. No radius change can
reconcile it, and retrying twice before failing only wastes time and hides the
real message.

The usual cause is `--zval` given alongside `--core-hole`. A core hole
**raises** the valence charge by one, because the electron was removed from the
core:

$$ z_{\text{valence}} = Z - n_{\text{core}} $$

Fewer core electrons, larger `z_valence`. See
[Tutorial 4](../tutorials/04-copper.md#what-the-core-hole-did-to-the-recipe).
The fix is to drop `--zval` and let the engine compute it.

---

## Failures the auto-fix engine cannot help with

### `implausible z_valence`

```text
Cs   ERROR: implausible z_valence=-5.0000000000000000
```

A negative or absurd valence charge means the reference configuration asks for
a core larger than the nucleus. `ld1.x` computes it, writes the file, and
exits 0 — so this check exists because the engine will not make it for you.

If it happens with a shipped recipe, that is a bug in the recipe database and
should be reported. One such case is documented as a worked example in
[Errata](../reference/errata.md): upstream PSlibrary's low-cutoff caesium asks
for `[Xe] 4f14`, which is 68 electrons in an atom with 55.

If it happens with `--config`, count the electrons in your configuration.
A noble-gas shorthand already includes everything up to that element — `[Xe]`
is 54 electrons and does **not** contain 4f, which first fills at Z=58.

### An engine is missing

```text
ERROR ONCVPSP (Hamann) is not built
      -> pseudoforge engines build oncvpsp
```

The fix command is in the message. `pseudoforge doctor` lists everything
missing at once. If you have the engine installed elsewhere, point at it
instead of building a second copy:

```bash
pseudoforge config --set ONCVPSP_BIN=/usr/local/bin/oncvpsp.x
```

### A conversion is refused

```text
ERROR gth -> upf is refused
```

```bash
pseudoforge convert --why gth upf
```

This is not a missing feature. Each refusal is a statement that the target
format needs data the source does not contain, so producing a file would mean
constructing the missing part and labelling the result with the source's name.
See [Convert between formats](convert-formats.md) and the reasons in
[Formats](../reference/formats.md).

### An engine cannot do what you asked

```text
ERROR ONCVPSP (Hamann) cannot make us pseudopotentials (it does: nc)
ERROR AtomPAW cannot generate meta-GGA with a relativistic solver.
```

Checked before anything runs, so nothing is half-written. The message names the
constraint and the way out.

---

## Known engine-specific limitations

These are properties of the engines, not of PseudoForge, and are documented on
each engine's page.

**APE** fails for a handful of elements where the l-gap between channels is too
small for its construction. See [APE](../reference/engines/ape.md).

**ADPACK** needs widened radii for tellurium; the auto-fix engine handles it,
and the retry is recorded. See [ADPACK](../reference/engines/adpack.md).

**AtomPAW** writes `xc_functional type="LDA"` in PAW-XML regardless of the
actual functional. The numbers are right; the label is wrong. PseudoForge warns
and the warning reaches the provenance. See
[AtomPAW](../reference/engines/atompaw.md).

**AtomPAW meta-GGA** is non-relativistic only — refused rather than attempted.

---

## When nothing works

Reproduce it by hand. PseudoForge keeps the exact input it used:

```bash
cat ./out/inputs/Cs.pbe-spnl-rrkjus_psl.1.0.0.in
cd /tmp && ld1.x < ~/out/inputs/Cs.*.in
```

If the engine fails the same way on its own input, the problem is the recipe or
the engine, and you have a minimal reproducer to send upstream. If it succeeds
by hand and fails under PseudoForge, that is a PseudoForge bug worth reporting
with both the input and the log.

Useful while investigating:

```bash
pseudoforge generate ... --no-autofix -v      # raw failure, verbose
pseudoforge generate ... --dry-run            # what would run, without running
PF_KEEP_SCRATCH=1 pseudoforge generate ...    # keep the working directory
```
