# The wizard

`pseudoforge` with no arguments starts a guided flow. It asks in the order the
decisions actually depend on each other, and each screen says what the choice
*costs*, not just what it is called.

```bash
PseudoForge              # guided flow
pseudoforge wizard       # same thing, explicitly
```

With `whiptail` or `dialog` installed you get the full-screen version; without
either, the same questions are asked as plain text. Nothing is only reachable
through one of them.

---

## The flow

### 1. Pseudopotential type

PAW, ultrasoft, or norm-conserving. This choice is first because it determines
which engines and which libraries are even possible: `ld1` and `atompaw` make PAW;
`ld1` and `uspp` make ultrasoft; `oncvpsp`, `ld1`, `opium`, `ape`, `fhi98pp`, `gth` and `adpack` make NC.

### 2. Functional

Filtered to what can actually be generated, with the consequence spelled out.

Atomic generators solve LDA and GGA only. Choose a meta-GGA, a hybrid or a van
der Waals functional and pseudoforge generates with its accepted semilocal parent
and tells you which: SCAN → PBE, B3LYP → BLYP, vdW-DF → revPBE. The file it
writes is genuinely a PBE (or BLYP, or revPBE) pseudopotential. That is not a
compromise — it is what every published library does, and what you should cite.

### 3. Relativity

Only asked when it can change the answer. If every element you picked is light
enough that spin-orbit splitting in the valence is negligible, the question is
skipped and scalar-relativistic is used.

### 4. Library

Filtered to those that support your type, each labelled with what PseudoForge can
actually do for it:

- **generate here** — PseudoForge reproduces that library's own recipes with an
  atomic code on this machine. All `psl-*` profiles: the recipes are
  byte-identical to PSlibrary's own inputs (bar the declared errata in
  `data/psl/ERRATA.tsv`), verified by
  `tests/test_psl_roundtrip.sh`.
- **download or import** — the library is produced by a generator whose
  published parameters PseudoForge does not have and will not invent.

### 5. Where the files come from

The question the old menu never asked:

**Download** — the mirror first (`MIRROR_URL`), then the library's own site.
Usually the better answer: published tables have been through far more testing
than a fresh local run. What arrives is validated exactly like something
generated here — same structural checks, same optional cutoff scan, same report.

**Build here** — for the settings nobody publishes: a core hole for XPS, a
different valence partition, an unusual functional.

If you pick "build here" for a library whose parameters PseudoForge does not have,
it says so before doing anything, and the result is labelled a pseudoforge
pseudopotential rather than that library's:

```
About provenance

SG15 ONCV is produced by oncvpsp.

What makes it that library is its published table of cut-off radii and
projectors -- not the code that consumed them, and PseudoForge does not have
that table.

ONCVPSP will run, but the result is a PseudoForge pseudopotential and is
labelled that way in the file and in every report.  For a real
reproduction, supply the library's own input files with --params <dir>.
```

### Engine check (only when needed)

If building locally needs an engine that is not installed, PseudoForge offers:

1. **Auto-install** — compile it from the source archives, verify the binary
   runs, record the path. Prerequisites are installed through your package
   manager, and PseudoForge prints the exact command and waits for a yes first.
2. **Enter a path** — if you already have it somewhere.

`ld1.x` is the exception: PseudoForge does not build Quantum ESPRESSO, and says so
with the commands to build it yourself.

### 6. Elements

Symbols, names, atomic numbers, ranges (`1-18`), groups
(`transition-metals`, `lanthanides`, `main-group`), or `all` with exclusions
(`all !lanthanides`).

### Then: review, run, validate

The review screen shows everything, including the equivalent command line — so
you can rerun it, script it, or put it in a paper's methods section.

Generation isolates failures per element: one element that will not converge
does not stop the other ninety-two.

Afterwards PseudoForge offers validation, and explains what each check buys:

- **transferability** — re-solves the pseudo-atom in configurations it was not
  fitted to and compares against all-electron. Fast, and the check that catches
  a pseudopotential which is only right for its own reference configuration.
- **cutoff scan** — runs `pw.x` over a ladder of cutoffs to find where the total
  energy stops moving. Slower, and the one that tells you the `ecutwfc` to put
  in your input file.

Then `summary.txt`, `summary.csv`, `summary.json` and `summary.html`.

---

## Recipes

The review screen offers *Save these choices as a recipe*, and the main menu
offers *Start from a recipe saved earlier*. Both read and write the same files
as the command line, so a recipe saved here reloads with:

```bash
pseudoforge generate --recipe <name>
```

and a recipe saved on the command line appears in the wizard's list. See
[the quick start](../getting-started/quickstart.md) for the command-line side.

## Doing it without the wizard

Every wizard choice maps to a flag, and the review screen prints the exact
command:

```bash
# generate locally with a specific engine
pseudoforge generate -e Si,Ge,Fe -t nc --engine oncvpsp -x pbe --source local

# download from the mirror, then validate what arrives
pseudoforge generate -e Si,Ge -p gbrv -t us --source online --cutoff-scan

# reproduce a published library from its own inputs
pseudoforge generate -e Si -p pseudodojo -t nc --params ~/dojo-inputs/

# engines
pseudoforge engines list
pseudoforge engines build oncvpsp
pseudoforge doctor
```

| flag | meaning |
|---|---|
| `--engine <name>` | any of the nine -- see [Engines](engines.md) |
| `--source local\|online` | generate here, or download |
| `--params <dir>` | published generator inputs, for a real reproduction |
| `--mirror <url>` | override `MIRROR_URL` for this run |

---

## Keyboard

| Key | Does |
|---|---|
| ++arrow-up++ / ++arrow-down++ | move between choices |
| ++tab++ | move between the list and the buttons |
| ++enter++ | select |
| ++esc++ | cancel the current screen |
| a letter | jump to the first entry starting with it |

### Ctrl shortcuts are not available, and this is why

The design called for `Ctrl+G` to generate, `Ctrl+S` to save a recipe and
`Ctrl+Q` to quit. **They are not implemented, and they will not be.**

whiptail is a front end to newt, and newt reads its own keys. It offers no hook
for binding a control character, so a `Ctrl+G` handler would be code that never
runs — and a help screen advertising it would be promising something that
silently does nothing.

What is offered instead is **single-letter accelerators**: every menu entry can
be reached by typing the first letter of its label. That is a real feature of
the widget set rather than a workaround pretending to be one.

A test asserts that no code or help text claims Ctrl shortcuts work.

!!! note "Why this is on the page rather than in a footnote"
    A limitation that is documented where someone will actually read it is a
    known constraint. The same limitation buried at the bottom is a surprise
    waiting to happen, and surprises cost more than missing features.

## The doctor panel

*Check this machine*, from the main menu. It renders **the same records** the
CLI report and the JSON endpoint use — `doctor_checks` runs once and produces
records; three renderers display them.

That is why the three can never disagree about what is installed. The panel is
sized to fit inside 80x24, which a test asserts even in the worst case where
everything is missing and the list is longest.

## The 80x24 rule

Every dialog fits an 80x24 terminal. Not a preference — whiptail fails
**silently** on a box larger than the terminal, and "cannot draw" and "user
cancelled" are indistinguishable to the caller.

Geometry is clamped with `ui_fit_h` / `ui_fit_w`, and a test scans the module
for any dialog asking for more.

## Two more whiptail traps, in case you extend it

**Dash-prefixed tags are eaten by the option parser.** A menu entry whose tag
starts with `-` is read as an option to whiptail itself.

**Cancel is exit 1; Escape is exit 255.** Treating them the same means losing
the difference between "go back" and "get me out of here".
