# Quick start

From nothing to a validated pseudopotential. Five minutes, assuming
[installation](installation.md) is done and `pseudoforge doctor` is happy.

Running `pseudoforge` with no arguments opens the full interactive Terminal
User Interface (TUI). If you prefer a step-by-step guided flow, run
`pseudoforge wizard`. For scripts and automated runs, use the command-line
interface (CLI) shown below.

## 1. Check the machine

```bash
pseudoforge doctor
```

You need at least `ld1.x` found. Everything else can wait.

## 2. See what would happen, before it happens

```bash
pseudoforge recipe Si -t paw -p psl-high -x pbe
```

```text
 &input
   title='Si',
   zed=14.,
   rel=1,
   config='[Ne] 3s2 3p2 3d-1',
   iswitch=3,
   dft='PBE'
 /
 &inputp
   lpaw=.true.,
   pseudotype=3,
   file_pseudopw='Si.pbe-n-kjpaw_psl.1.0.0.UPF',
   ...
```

That is PSlibrary's own input deck for silicon, rendered with the functional
and relativity you asked for. Nothing has run yet.

## 3. Generate

```bash
pseudoforge generate -e Si -t paw -p psl-high -x pbe -o ./my-first
```

```text
== Generating ==
INFO  generating 1 element(s) with 4 parallel job(s)
OK    Si  ->  Si.pbe-n-kjpaw_psl.1.0.0.UPF  (1s)

== Transferability tests (ld1.x, iswitch=2) ==

 ELEM PSEUDOPOTENTIAL                    STATUS    PARAMS      TRANSFER   ECUT/RHO     NOTE
 ----------------------------------------------------------------------------------------------------
 Si   Si.pbe-n-kjpaw_psl.1.0.0.UPF       ok        n.1.0.0     excellent  -

 1 succeeded, 0 succeeded with warnings, 0 failed, 0 skipped (1 total)

 TRANSFER measured by: ld1 iswitch=2
```

`excellent` means the pseudopotential reproduced all-electron eigenvalues to
better than 1 mRy in five configurations it was **not** fitted to. See
[Validate a pseudopotential](../how-to/validate.md).

## 4. Use it

```bash
cp ./my-first/pseudos/*.UPF $ESPRESSO_PSEUDO/
```

```text
ATOMIC_SPECIES
  Si  28.0855  Si.pbe-n-kjpaw_psl.1.0.0.UPF
```

PAW wants `ecutrho` around 8× `ecutwfc`. To measure rather than guess, add
`--cutoff-scan` (needs `pw.x`).

## 5. Know what you made

The generated project directory is completely self-contained:

```text
my-first/
├── PROVENANCE.txt
├── manifest
├── state.tsv
├── inputs/
│   └── Si.pbe-n-kjpaw_psl.1.0.0.in
├── logs/
│   ├── Si.log
│   └── pseudoforge.log
├── pseudos/
│   ├── CITATION.txt
│   ├── LICENSE.txt
│   └── Si.pbe-n-kjpaw_psl.1.0.0.UPF
├── reports/
│   ├── summary.csv
│   ├── summary.html
│   ├── summary.json
│   └── summary.txt
└── tests/
    ├── Si.test.in
    ├── Si.test.out
    └── transferability.tsv
```

Check the provenance record written at generation time:

```bash
cat ./my-first/PROVENANCE.txt
```

```text
# PseudoForge 1.3.2 -- run provenance
# Generated 2026-10-23 20:47:37 +0330

tool.name=PseudoForge
tool.version=1.3.2
engine.id=ld1
engine.label=Quantum ESPRESSO ld1.x
engine.version=v.7.4
engine.build=445810ceecf7
engine.binary=/usr/local/bin/ld1.x
engine.upstream=https://gitlab.com/QEF/q-e
profile=psl-high
family=paw
functional=PBE
functional.requested=pbe
relativity=scalar
source=local

# element	file	provenance	status
Si	Si.pbe-n-kjpaw_psl.1.0.0.UPF	n.1.0.0	ok
```

Keep this with your project. It is what answers "which of these three libraries
did the published numbers come from?" six months later.

---

## The same thing, guided

```bash
pseudoforge wizard
```

walks the same decisions as screens, explains each one, and ends on a review
screen showing the exact command line your choices add up to. It is a way of
learning the flags, not only of avoiding them.

Needs `whiptail`. Without it, `pseudoforge` prints the CLI usage instead.

---

## What to do next

**Learn the shape of it**
: [Tutorial 1: Carbon](../tutorials/01-carbon.md) — the same run, explained
  line by line, including why a column can be empty.

**Understand the choices**
: [Concepts](concepts.md) — the ten layers a pseudopotential is decided by.

**Do a specific thing**
: [Choose an engine](../how-to/choose-an-engine.md) ·
  [Choose a functional](../how-to/choose-a-functional.md) ·
  [Troubleshoot a failure](../how-to/troubleshoot.md)

**Make a lot of them**
: [Tutorial 7: A batch](../tutorials/07-batch.md) — 29 elements, parallelism,
  resume.

---

## Three things worth knowing early

**The functional must match.** A PBE pseudopotential used in an LDA
calculation is a real, measurable error. Generate with what you will run with.
[Why](../how-to/choose-a-functional.md).

**`-o` is where, not what.** Every run writes a self-contained project
directory: `pseudos/`, `inputs/`, `logs/`, `tests/`, `reports/`,
`PROVENANCE.txt`, `state.tsv`. Copy `pseudos/` into your `pseudo_dir`; keep the
rest.

**Re-running is cheap.** A second run of the same command skips what is already
done. Delete a file from `pseudos/` to regenerate just that element.
