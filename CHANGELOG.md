# Changelog

## Version 1.3.3 — installation system, first DOI

### What this release adds

`install.sh` gained `--deps`, `--bootstrap`, and `--dry-run`. `--deps`
installs the build dependencies with the host package manager after
showing the exact command and asking for confirmation. `--bootstrap`
does the same, then builds every engine PseudoForge can build. Nothing
is downloaded from GitHub without the user seeing what and where.

The source archives for eight engines, plus the two libraries APE and
ONCVPSP link against, are pinned in `engines-src/` with SHA256 checksums
in `engines-src/MANIFEST.txt`. `build.sh` fetches from there and
verifies the checksum before building. Total about 105 MB, inside the
repository so a fresh clone has everything it needs offline.

ADPACK is now buildable: `build_adpack` patches the upstream
`source/makefile` to use the system's BLAS and LAPACK instead of the
author's hardcoded `/home/ozaki` paths, and `build_all` includes it.
Eight engines are built by PseudoForge itself.

Quantum ESPRESSO's `ld1.x` is fetched and built on demand. The first
time a run needs it, PseudoForge asks; if the user says yes, it
downloads the QE source (~500 MB), builds only the `ld1.x` target
(~15-30 minutes), installs the binary under
`~/.pseudoforge/engines/bin/`, and records the path in the user's
config. The prompt appears from the CLI, from `tui_review`, and from
`wizard_main`.

`doctor` now probes BLAS, LAPACK, unzip, and python3 in addition to the
compilers. `pseudoforge doctor --check` exits non-zero when a required
dependency is missing; the default `doctor` still exits 0 and stays
informational.

### Verified

`tests/test_psl_roundtrip.sh` runs against the PSlibrary 1.0.0 source
archive and confirms 565 generation decks and 462 test decks match
upstream, with the two caesium decks differing only where
`data/psl/ERRATA.tsv` declares a correction. The byte-identical claim
in `README.md` and `CITATION.cff` is backed by a passing test.

### Documentation

Every markdown page reconciled with the code in a dedicated pass.
`installation.md` describes what `install.sh` actually does today. The
`engines.md` page names eight buildable engines and one external
(Quantum ESPRESSO). `adpack.md` no longer calls itself external.

### First DOI

Zenodo mints a concept DOI and a version DOI for this release.
`MD_DOI[pseudoforge]` in `lib/metadata.sh` is set to the concept DOI so
every citation PseudoForge prints resolves. The suggested archive title
is "PseudoForge — a multi-engine pseudopotential generator and
validator".

---

## Installation system overhaul and automated engine builds

A full overhaul of the installation system added automated dependency management and reliable offline engine builds. The `install.sh` script now supports `--deps`, `--bootstrap`, and `--dry-run` across Debian, Fedora, Arch, and macOS; `doctor --check` provides non-zero exit validation for required tools. Source archives for eight engines and their supporting libraries are packaged in `engines-src/` and verified against `MANIFEST.txt` by `build_fetch_src` in `lib/build.sh`. ADPACK is now compiled from source via `build_adpack` with an automated makefile patch for standard compiler flags and system BLAS/LAPACK, and is included in `build_all`. Quantum ESPRESSO's `ld1.x` is handled via an on-demand prompt-and-install flow in `build_ld1` and `pf_ask_install_ld1`, which fetches QE source, builds only the `ld1` target, installs it into `~/.pseudoforge/engines/bin`, and records `LD1_BIN` in configuration, while also discovering existing QE installations across standard system directories.

## Comprehensive audit, gate hardening, and full documentation pass

The post-audit execution pass resolved twelve findings across the server,
engine declarations, configuration templates, and testing infrastructure.
In the HTTP server, a duplicate download handler was removed in favor of a
single streaming route using `FileResponse` with byte-range support, and the
route table gained `/api/version` and `/api/routes` to mirror the endpoints
declared by `server/app.py`. ADPACK was explicitly marked as an external
installation in the engine registry, and `build_all` now excludes it rather
than attempting an unsupported automated build. The test suite's offline
resilience was improved by seeding the SG15 cache so mirror and fallback
tests run without network access, while `test_psl_roundtrip.sh` now exits with
code 77 when upstream source tarballs are absent, correctly recognized by
`run_tests.sh` as a skip rather than an unearned pass. The configuration
template was expanded to cover environment variables for all nine engines,
and its comments were corrected to reflect the official-first download order.
The audit gate itself was made strictly enforceable: `tools/audit.sh` now
exits non-zero on failure, `run_expect_fail` asserts an expected error pattern
so failures occur for the right reason, and the mode distinction between
fast and full audits is recorded in `AUDIT.md`. In the data tree, the CP2K
Delta benchmark parameters for `cp2k-gth` are now documented in a dedicated
local README.

A subsequent hardening pass resolved a potential hang during the full audit.
When run on a workstation where `~/.pseudoforgerc` points `LD1_BIN` at a real
`ld1.x` binary, MPI socket initialization could block indefinitely on an
empty stdin; `tools/audit.sh` and `tools/audit-interfaces.sh` now isolate
`PF_RC` and redirect standard input from `/dev/null` so full mode cannot hang.
Configuration precedence was corrected so that an environment variable set
by the caller consistently wins over the file on disk. A formatting defect in
the audit output where literal newline escapes glued adjacent test records
together was resolved, cleanly separating tests that were previously
conflated—such as `validate psp8` and `plot on a project`, and the
profile-coverage refusal alongside `fetch sg15`—and restoring an honest check
count.

Finally, a complete documentation pass audited every markdown document across
the repository—including the project README, CITATION.cff, getting-started
guides, tutorials, task how-tos, architectural and physics explanations,
contributing guides, and engine reference pages. Stale output blocks, command
options, module counts, and layer definitions were reconciled with the actual
code in `lib/`, verifying that every claim, command, and cross-reference
throughout the documentation accurately reflects the state of the codebase.

## 1.3.2 — Post-audit fixes

- **`cmd_generate` no longer demands `ld1.x` for downloads or non-QE engines.**
  `cmd_generate` checked `deps_have_ld1` unconditionally before inspecting
  `SPEC[source]` or `SPEC[engine]`, so `--source online` and `--engine oncvpsp`
  failed on machines without Quantum ESPRESSO. `ld1.x` is now required only
  when `SPEC[source]=local` and `SPEC[engine]=ld1`.

- **`fetch_candidate_names` returns a bare filename for `sg15`.**
  The `sg15` branch prefixed `"${base%/}/upf/"` using `base` inherited from
  `fetch_mirror_urls`, doubling the mirror URL prefix. It now returns `$hit`
  alone, like every other profile branch.

- **`xc_engine_native` no longer reports proxy functionals as native to AtomPAW.**
  When `XC_NO_ENGINE_LOOKUP=1` was set, `xc_generator` fell through to
  `XC_PROXY[$id]` (`pbe`), causing `ib_atompaw_xc` to succeed for `scan`,
  `tpss`, `m06l`, `pbe0`, `rvv10`, and `vdw-df2`. `xc_engine_native` now
  answers true on AtomPAW only for `pz`, `lda`, `pw`, `pbe`, `pbesol`,
  `r2scan`, and `r2scan-01`.

## One guided flow, and an audit that reaches the corners it used to miss

The TUI had grown three entry points that all claimed to do the same
thing: `tui`, `wizard`, and an `oldtui` nobody remembered adding.  They
had drifted.  `tui` ran nine layers; `wizard` ran a ten-step list of its
own; `oldtui` ran a legacy menu.  A user reading the help page could not
tell which one was current.

And the interface audit that was supposed to catch this stopped at the
review screen.  Every check ran through the layers and looked at SPEC;
none of them asked what happened when the user pressed Run.

### The flow is one flow now

- **`tui_main` is the only entry point.**  `pseudoforge tui`,
  `pseudoforge wizard`, and a bare `pseudoforge` on a terminal all end
  up there.  `wizard` is the shortcut past the menu; when there is no
  whiptail or dialog, both fall through to the plain-text
  `wizard_main`.  The dispatcher had `wizard` in the `''|tui|menu|wizard`
  case, so its own case further down never ran and `pseudoforge wizard`
  opened the full menu instead of the guided flow.  That is fixed.

- **The menu gained the eight entries it was missing.**  `validate`,
  `import`, `reports`, `settings`, `profiles`, `recipes`, `xc`, and a
  separate `browse` -- fourteen in all.  A menu item that exists in the
  CLI and not in the TUI is a user told to learn the command line.

- **The guided flow gained the source layer.**  A run that used to
  build locally without ever asking now offers "download, or build
  here" as its own screen, between profile and engine.

- **The engine layer asks before skipping.**  `tui_layer_engine` calls
  `ui_ensure_engine` first; an uninstalled engine used to be silently
  dropped from the list.

- **Dead code removed.**  `ui_main`, `ui_wizard`, `ui_doctor`,
  `pf_spec_init_safe`, and the `oldtui` dispatcher entry.  A scan of all
  586 functions in `lib/` for zero external references returns 0 --
  except `deps_report`, which `cmd_doctor` still uses.

### Two bugs the audit's own drive-through found

- **`cli_check_spec` preferred the profile's format declaration over
  the engine's ability.**  A TUI run for APE picked `upf` because APE
  writes only `upf`; the profile declared `upf xml`; `cli_check_spec`
  believed the profile and refused with "APE cannot write xml".  The
  order is now: an explicit `--format`, then the profile's declaration
  *if the engine can honour it*, then SPEC, then the default.

- **`ui_pick_format` skipped without setting SPEC.**  For engines that
  write one format (APE -> upf, fhi98PP -> cpi, ADPACK -> openmx), the
  menu never opened and `SPEC[formats]` kept the `spec_init` default,
  which the next stage then refused.  It now sets what the engine
  writes before returning.

### The audit grew from 87 checks to 155

The new sections are about the surfaces a user meets, not the surfaces
a developer tests:

- **C -- the TUI advanced screen**, 6 keys -> 23.  Every user-settable
  key is driven through the scripted whiptail and asserted in SPEC.
- **D -- wizard steps**, 1 -> 15.  Each of the seven steps runs in its
  own shell, so a `SPEC` it sets is still there when the next one runs.
- **G -- TUI per-engine generation**, new, 9 checks.  For each engine,
  the audit sets SPEC the way the layer walk would have, calls
  `tui_review` directly, and asserts the engine produced files and a
  report.  Before this, the TUI had never been driven past review.
- **H -- TUI top-level menu.**  Every menu tag has a case handler;
  every handler function exists; `tui_main` offers at least fourteen
  entries.
- **I -- config file.**  `--show` / `--path` / `--set` / `--edit`
  round-trip, and the `.psmakerrc` -> `.pseudoforgerc` migration in an
  isolated `$HOME`.
- **J -- recipe round-trip across the interfaces.**  A recipe saved by
  the CLI reloads byte-identical from the TUI, and vice versa; a file
  that claims a newer format, or carries a key this version does not
  know, is refused rather than read with the older one.
- **K -- engine-specific menus.**  `fmt_for_engine` returns exactly the
  registry's list for each of the nine engines; `ui_pick_format` on a
  single-format engine opens no dialog and sets SPEC; `ui_pick_engine`
  on `psl-high`/`paw` is ld1 only, on `sg15`/`nc` is oncvpsp or opium,
  on `gbrv`/`us` is uspp only.
- **L -- refusal matrix in the TUI.**  `--projector` on oncvpsp,
  `--upf 1`, `family=paw` on oncvpsp, `--rcut-scale` on uspp, and a
  meta-GGA on AtomPAW are refused after the Review screen and before
  anything is written.  The CLI refuses the same five.

### A help text bug found while updating the help text

`cli_usage` prints through an *unquoted* heredoc, so anything in
backticks runs.  The new line "also what a bare `pseudoforge` runs"
made every `--help` invocation try to execute the word `pseudoforge`,
which is not on `PATH`, and print `command not found` over the usage
text.  The reference is now plain text.

---

## The interfaces, checked against the core after the changes

The five weeks of changes -- format disambiguation, AtomPAW's r2SCAN path,
the `--projector` and `--rcut-scale` restrictions, `--variant` and
`--author` and `--rho0`, the renamed element-selection tag, the store's
`encoding` field -- landed in the core.  The question was whether they
landed in the CLI, the TUI and the wizard, where a user meets them.

They had not, in five places.

### Five bugs the diagnostic found

- **The TUI's step titles were wrong.** The dialogs said "Step 1 of 6",
  "Step 2 of 6", and so on, through the pseudopotential settings.  The
  TUI has nine layers, not six.  The number was written once and never
  updated as the flow grew.  The wizard keeps its own "Step N of 6:"
  because its flow really is six numbered questions.  The TUI titles are
  now just the layer's name -- no count.

- **`pseudoforge params --help` answered "unknown subcommand '--help'".**
  So did `profile --help` and `xc --help`.  Each of those subcommands has
  its own sub-subcommands (status, fetch, path / list, new, edit, remove),
  and the parser treated `--help` as an unknown one.  All three now have
  a case handler for `-h|--help` before the subcommand dispatch.

- **`pseudoforge compare --help` printed "ERROR usage: ..."** -- the
  usage line came from `die`, which prefixes with the word ERROR.  A user
  who asks for help has not made a mistake.  `compare` now answers with
  plain usage text and returns zero.

- **Six subcommands were missing from `./pseudoforge help`.**  The
  dispatcher accepted `compare`, `citation`, `params`, `profile`, `xc`
  and `api`; the help page did not mention them.  `cli_usage` now lists
  all six with a one-line summary each.

- **`tests/run_tests.sh` still expected the old TUI titles.**  Once the
  "Step N of 6" prefix came off, the mock-whiptail answers no longer
  matched.  Five `dlg` calls in the run suite updated.

### `tools/audit-interfaces.sh` -- the audit that keeps them caught

A permanent script, in the spirit of `tools/audit.sh` but organized by
interface.  Six sections:

- **A. CLI help completeness** -- every subcommand answers `--help` with
  non-empty output; every canonical subcommand appears in `pseudoforge
  help`; every top-level flag in `cli.sh` is either in the help text or
  on an explicit list of subcommand-specific flags, with the reason it is
  on the list.
- **B. TUI screen reachability** -- every entry in `tui_layers()` has a
  handler function that exists; every `ui_pick_*` a layer names exists;
  the element-selection menu emits the renamed `finish` tag.
- **C. TUI advanced screen reaches SPEC** -- one check per user-settable
  key, driving the advanced screen with the scripted whiptail and
  asserting the key lands in SPEC.
- **D. Wizard text-mode entry** -- the wizard's plain-text flow reaches
  the family prompt with `PF_FORCE_TEXT=1` and piped input.
- **E. Doc paths from shell code** -- every `docs/*.md` path named in
  `lib/tui.sh`, `lib/wizard.sh`, `lib/ui.sh` or `lib/cli.sh` exists.
- **F. CLI subcommand smoke** -- thirteen commands that must return zero:
  `native list`, `engines path`, `convert --why`, the four `list` pages,
  `doctor`, `config --show`, `citation`.

The slow per-engine TUI matrix is stubbed behind
`PF_SLOW_INTERFACES=1`; it will fill in as the individual screens are
written up.

`run_tests.sh` now runs the fast sections on every invocation.  The
suite is 169 checks.

### One property the audit keeps, on purpose

The five bugs above share a shape: the code changed, the interface did
not, and nothing failed loudly.  A help page that omits a working
subcommand is not a crash; a step count that is off by three is not a
crash; a `--help` that answers "unknown subcommand" is annoying but not
broken.  The user notices all of them, and none of them are the sort of
thing a unit test usually reaches.  `audit-interfaces.sh` is a place to
put them.

## Dead code removed, shellcheck clean, three real bugs found

The code review the user asked for: every module read, every function
checked for a caller, every shellcheck warning resolved or explained.

### Three bugs that only a line-by-line read would have found

- **`lib/ui.sh`, the "source" line of the review screen.** A printf whose
  format string contained a real newline and whose continuation used
  literal `\n` wrote the two characters `\` and `n` where the review was
  supposed to say "download (official source, then mirror)" or "build
  here with ld1.x".  The user's review screen before any run has been
  showing the wrong thing.

- **`lib/recipe.sh`, `lib/convert.sh`, `lib/input_builder.sh`,
  `lib/validate.sh` -- `local a=$1 b=${...[$a]:-}`.** In bash, every
  variable in a single `local` is expanded before any of them is
  assigned.  So `outdir=${3:-$(dirname "$src")}` with `src=$1` on the
  same line computed `dirname` of the *previous* value of `$src`, which
  was empty.  Six places across four files.  Split into two locals each.

- **`lib/run.sh:93` -- a case pattern `*paw*|newd_paw*` where the second
  alternative is a subset of the first and never fires.** Dead branch.
  Removed.

### Dead functions removed

- `ib_opium_nlm` (input_builder.sh, 28 lines with its comment)
- `native_attr` (http.sh, 108 lines) -- its logic is inlined into
  `native_index_build` now; the function was the pre-inline version
- `params_ensure` (params.sh, 23 lines) -- `params_fetch` is called
  directly from cli.sh, this was a wrapper with no callers
- `tui_screen_header` (tui.sh, 12 lines)

171 lines gone, and the one comment that still mentioned `native_attr`
by name rewritten to describe the history instead of a function that is
no longer there.

### ShellCheck

380 warnings, all analysed.  The 269 that came from the module
architecture (dynamic `source` loops, variables assigned in one module
and read in another) are silenced at `.shellcheckrc` with the reason for
each.  The 111 that remained were checked line by line:

- **SC2155** (`local x=$(cmd)` masks the command's exit code): 5 fixes,
  split into `local x` and `x=$(cmd)`.
- **SC1007** (`VAR= cmd` vs `VAR='' cmd`): every case made explicit.
- **SC2010** (`ls | grep`): 3 sites, replaced with a glob or `find`.
- **SC2046, SC2206, SC2209, SC2218, SC2128, SC2178, SC2140, SC1087**:
  each fixed or explained with a directive at the function.
- The last one was a real bug in `report.sh` -- the same newline-in-printf
  pattern as the ui.sh one, in the HTML report's engine section.

`shellcheck -S warning lib/*.sh tools/*.sh tests/*.sh` is now silent.

### Dead code that is not dead

Six functions looked unreachable but are public API exercised only by
the test suite:

- `nml_add_card`, `nml_card_count` -- namelist
- `pf_confirm_use`, `pf_sink_failed`, `pf_sink_records` -- sink
- `tui_run_with_progress` -- TUI

They stay, and the naming test in `tests/test_custom.sh` covers them
indirectly by checking that the interfaces they serve agree with the CLI.

### Tests wired in

`tests/test_interfaces.sh` (31 checks) and `tests/test_ui.sh` (30 checks)
were separate files that `run_tests.sh` never called.  Both pass, both
now run as part of the default suite.

`tests/test_index.sh` was reading `$HOME/pf-native` after `run_tests.sh`
had overridden `$HOME` to a temporary directory, so it skipped and the
wrapper reported a pass for a check that never ran.  The wrapper now
hands it the same store path it checked.

## Custom settings: every key on the command line, and the menus agreeing

The CLI has always accepted the full ld1.x override set -- core holes for
XPS, fractional charge for virtual crystals, NLCC, extra projectors, the
local channel, the radial grid, GIPAW, spin polarisation.  What had never
been checked was that the TUI and the wizard offered the same set, and that
a menu option was always one the code would accept.

Both were wrong in places.

### A menu option the code refuses

The advanced screen offered UPF v1 as a choice.  `cli_check_spec` refuses
`--upf 1` outright -- QE 7.x's ld1.x no longer writes v1 -- so a user who
picked it got a refusal they did not ask for.  The option was a promise the
code does not keep.

Removed from the advanced screen and from the config panel's "Default UPF
format".  The `--upf` flag stays, because a recipe file carries it and a
script may pass it; the only value it can carry is 2, and the CLI is where
that is enforced.

### Three keys the CLI had and the TUI did not

- **`--variant`** -- a specific PSlibrary variant tag, rather than the
  first the recipe database supplies.
- **`--author`** -- the author string written into the file.
- **`--rho0`** -- the NLCC core charge at the origin, next to `--rcore`.

All three were settable from the command line, from a saved recipe, and
from nowhere in the menus.  A user who wanted any of them had to leave the
TUI, which is not what a guided interface is for.

### Two dead case handlers

Removing the UPF v1 menu item left its `case` branch and the config panel's
counterpart behind.  A menu item that cannot be selected is dead; a branch
that no longer has a matching item is dead too.  Both removed.

### The test that would have caught all of it

`tests/test_custom.sh` (new) checks the property that matters: **every key
a user can set is reachable from the command line, from the TUI advanced
screen, and appears in the flag table the recipe format uses.**  It also
runs the guard rails -- `--projector` and `--rcut-scale` are refused on the
engines that cannot apply them -- and drives the advanced screen through
the scripted whiptail to check that the SPEC it produces is the SPEC the
CLI would have produced from the equivalent flags.

Sixty-nine checks, and the three classes of bug above each fail at least
one of them.

### The wizard does not have an advanced screen, on purpose

The wizard asks the six questions a pseudopotential is decided by --
formulation, functional, relativity, library, source, elements -- and stops
there.  Everything on the advanced screen is an override of a library
recipe, and a wizard user who has not yet seen a recipe has nothing to
override.  The custom test says so: it drives the wizard in text mode and
asserts that whatever it picks ends up in the same SPEC the CLI uses, not
that the wizard offers every flag.

## The store was telling the index one thing and the disk another

Three bugs lived in the gap between what the store build writes, what the
index records, and what the site serves.  All three were silent: nothing
failed, nothing warned, and the index said everything was fine.

### The index called every file gzip, even the plaintext ones

`native_index_build` wrote `encoding=gzip` for every row it produced.  The
server sets `Content-Encoding: gzip` from that field, so a `.abinit` or
`.cpmd` file -- both plaintext, because the build script's gzip pattern
listed only seven extensions -- would have been announced as gzip and
delivered as text.  A browser downloading `Fe.pbe-atompaw.abinit` would
have saved gzip bytes under a `.abinit` name.

Two fixes:

- **`build-native-store.sh`** gzips everything under `*/pseudos/*` except
  the two metadata files (`CITATION.txt`, `LICENSE.txt`), instead of a
  list of extensions.  The old list missed `.abinit`, `.cpmd`, `.fhi`,
  `.psf`, `.recpot`, `.ncpp`, `.teter`, `.qso`, `.casino`, `.champ`,
  `.uspp`, `.van` and `.pao`.
- **`native_index_build`** reads the extension to decide: `.gz` is gzip,
  anything else is plain.  A file's own name is the only signal this needs.

`tests/test_index.sh` checks both directions: every `.gz` is a real gzip
magic number, and the index's `encoding` column matches the bytes on disk.
It runs in the full suite, sampled in `--quick`.

### Two formats shared one id

`.abinit` is atompaw's PAW dataset (`paw-abinit`) and cp2k-gth's psp3
layout (`gth-abinit`).  `.cpmd` is opium's CPMD writer (`cpmd`) and
cp2k-gth's CPMD layout (`gth-cpmd`).  `.xml` covers three: QE's UPF XML,
paw-xml, and opium's QSO.  The old index mapped every extension to its raw
value, so a row labelled `abinit` could have been either format and the
index could not say which.

`native_index_build` now looks up `(profile, extension)` in the format
registry.  A profile declares its formats, each format declares its
extension, and the pair is what names a file.  When the extension is not
one the profile declares, the old fallback still applies.

The count proves it worked: `paw-abinit: 531`, `paw-xml: 529`,
`gth-cpmd: 302`, `gth-abinit: 302`, `siesta: 145`, `qso: 750`,
`openmx: 58` -- and zero rows labelled with the bare extensions
`abinit`, `psf` or `vps`.

### Resume after a gzip pass regenerated every file

`build-native-store.sh` compresses a run's output after the run finishes.
A later `--resume` pass looked for the file by its plain name,
`$PROJECT_DIR/pseudos/Si.pbe-gth.gth`.  The file was now
`Si.pbe-gth.gth.gz`, so every element looked missing and the whole
combination was regenerated.  The gzip step then refused to overwrite the
existing `.gz` and the plaintext stayed behind.

The store grew by 1,724 duplicate files before anyone noticed.  They are
gone.

- **`state_should_run`** in `lib/project.sh` now counts a `.gz` beside
  the plain name as the same file.
- **`build-native-store.sh`** has a cleanup guard: after gzip, any
  plaintext file whose `.gz` sibling exists is removed.  A store built
  before the fix does not need to be rebuilt from scratch.
- **`test_engine_matrix.sh`** gained a resume section: for every row it
  gzips the first run's output, runs `generate` again with the same
  arguments, and asserts that nothing changed.  Twelve more checks that
  would have caught this the first time.

### What the fixes cost

The store is unchanged in content -- same 28,527 files, same bytes -- with
the `.gz` and plaintext duplication removed.  The index is smaller by
1,724 rows and every remaining row says something true.

`tests/test_index.sh` is new and runs in `--all`.  `tests/test_engine_matrix.sh`
is new, runs the real engines, and is invoked separately because the main
suite uses mock binaries and a temporary HOME.  `run_tests.sh --all` names
it in a SKIP line so an operator knows it exists.

## The documentation audited, and four pages the code already implied

Documentation rots one flag at a time. This session built a checker that
finds the rot mechanically, then fixed what it found.

### The checker

- **`tools/check-anchors.py`** — every `[text](file.md#anchor)` link is
  resolved against the headings MkDocs would build. `test_docs.sh` checked
  the file existed but not the fragment, so a link to
  `limitations.md#--projector` was as broken as one to a missing file and
  nothing said so. Thirty-three such links were live.
- **`tests/test_docs.sh`** runs the checker as its own section. The docs
  suite is now 14 checks, not 13.

### Four pages the code already implied

- **`reference/coverage.md`** — generated from the profile registry: which
  element is covered by which profile, with what families, functionals and
  relativity. Engine-kind profiles show `any` rather than 0, because they
  build the deck from the ground state rather than caching one.
- **`reference/limitations.md`** — every refusal in one place: formats that
  cannot be produced, conversions that do not exist, engine restrictions,
  the meta-GGA proxy, flags with restricted scope.
- **`reference/store.md`** — what the pre-built store is, how it is
  indexed, how it is rebuilt. Reads from the store's own `index.tsv`.
- **`reference/upstream.md`** — the OPIUM d-shell crash (issue #1, PR #2),
  the AtomPAW `type="LDA"` defect on meta-GGA output, the APE GGA failure.
  What is reported, what is documented instead, and why.

### Fixed

- **`--projector` refuses outside ld1.** It was accepted by every engine,
  applied by ld1 only, and stamped `-xp` into the file name of the rest.
  The other engines did what they were asked; the bug was PseudoForge
  promising a change it did not make. Same class as `--rcut-scale` was.
- **`tools/gen_reference.sh::gen_profiles`** used `prof_is_generatable`,
  which only recognised `provenance=native|derived`, so every profile whose
  recipes are fetched or engine-built (atompaw, pseudodojo, gbrv, fhi, gth,
  uspp, adpack, cp2k-gth, hgh, opium) was marked "import only". The fix
  reads `params_kind`, and excludes `selection` so SSSP stays honest.
- **UPF v1, PSML, meta-GGA text** — stale claims removed from six pages.
  UPF v1 is refused now; PSML was never producible; the meta-GGA section in
  `choose-a-functional.md` describes both the proxy path and the AtomPAW
  native path.
- **06-scan tutorial** used `-p psl-high --engine atompaw`, which fails
  because `psl-high` declares `formats=upf xml` and AtomPAW does not write
  QE XML. Switched to `-p atompaw`, the profile built for it.
- **README** — the intro said "drives `ld1.x` and `pw.x`" and the
  limitations section said "`ld1.x` is the only atomic code PseudoForge
  drives"; both predate the multi-engine work. The meta-GGA section gained
  the AtomPAW native path. A superseded section and a duplicate engine
  table were deleted.
- **CITATION.cff** said "driving eight" engines; there are nine.
- **`.gitignore`** now ignores ABINIT artefacts (`CRASH`, `abitk.out`,
  `dummy`) left by a run that fails part way.

### Verified, not changed

The GTH claim — "reproduces all 322 published GTH tables exactly" — was
checked against `tests/test_gth.sh`, which computes 322 as the count of
(element, functional) pairs where both a `psp.par` file and a published
coefficient entry exist. The number is accurate.

### Final state

`tools/audit.sh` 57 PASS. `tests/run_tests.sh --all` 164 PASS.
`tests/test_docs.sh` 14 PASS. `PF_SLOW_TESTS=1 tests/test_docs.sh`
23 PASS (tutorials execute end to end).

## Meta-GGA (r2SCAN) via AtomPAW

AtomPAW is the one generator here that carries its own meta-GGA, and the
registry already declared r2SCAN as a functional whose proxy is PBE.  What
was missing was the profile declaration and two paths in the executor.

### Fixed

- **`atompaw.profile` declares r2SCAN.** `xc_available` gains `r2scan`;
  `rel_available` gains `nonrel`.  AtomPAW's meta-GGA solver is
  non-relativistic only -- the relativistic branch is not implemented
  upstream -- and the CLI already refuses the combination.
- **`exec_atompaw` writes both meta-GGA datasets.** Previously the
  no-UPF branch picked one of `-paw.xml` or `-paw.abinit` and dropped the
  other, so `--format paw-abinit,paw-xml` produced only the xml.  It now
  honours `SPEC[formats]` and writes whichever of the two was asked for.
- **`exec_install` accepts a same-file copy.** Some exec_* functions
  (exec_atompaw for meta-GGA) stage the file in `pseudos/` themselves and
  return the staged path; `cp X X` refuses that, so the branch now
  detects it.
- **`build-native-store.sh::plan` respects the meta-GGA rule.** The plan
  builder reads XC families from `data/xc.tsv` and skips
  `atompaw + metaGGA + rel != nonrel`, matching the CLI's own refusal.

### Store

`~/pf-native/atompaw` gains four combinations -- three GGA non-relativistic
plus r2SCAN non-relativistic -- for ~800 new files.  The store now
carries meta-GGA, and PseudoForge is the only open generator here that
produces an r2SCAN PAW dataset.

### Honest limitation

r2SCAN produces a PAW-XML and an ABINIT PAW dataset -- not UPF.
Quantum ESPRESSO 7.x has no place to put the kinetic-energy density that
makes a meta-GGA a meta-GGA, so QE cannot read a meta-GGA UPF even if
one were written.  The UPF writer in AtomPAW refuses cleanly:

    XC functional not compatible with atompaw2UPF!

That is AtomPAW's behaviour and Quantum ESPRESSO's limit, not a gap in
PseudoForge.  Users of meta-GGA should take the `.xml` (read by GPAW and
ABINIT) or the `.abinit` (read by ABINIT directly).

## OPIUM: ten output formats, and an upstream crash on d-shell elements

Until now OPIUM shipped only UPF in the native store, and the profile said
so. The other nine writers existed in the executor but were unusable: every
one of them crashed with SIGSEGV on any element whose valence l-shells are
not contiguous -- the 3d and 5d transition metals, i.e. roughly a third of
the periodic table.

### The bug

Six of the ten writers (FHI, NCPP, CPMD, CASINO, CHAMP, SIESTA) built the
scratch-file names `*.pot.ps.l=N` and `*.psi.ps.l=N` from the loop index
`i` rather than the real angular momentum `aorb_.lo[i]`. On Fe, whose
valence shells are {s, d}, the loop asked for l = 0, 1, 2 but the producer
wrote only l = 0 and 2, so `fopen("fe.pot.ps.l=1", "rb")` returned NULL
and the subsequent `fread(NULL, ...)` segfaulted.

This is OPIUM 4.1.0's own bug, not PseudoForge's. The other four writers
(UPF, recpot, Teter, QSO) already used the correct form and were
unaffected.

### Fixed

- **Six writers patched at build time.** `lib/patches/opium/apply.sh`
  runs between `build_prepare_src` and `configure` in `build_opium`,
  rewrites the six writers to use `aorb_.lo[i]`, and adds the missing
  `#include "common_blocks.h"` to `do_fhi.c` and `do_ncpp.c`. The
  upstream source tree is untouched on disk; the patch is applied to the
  working copy only, and is idempotent.
- **Fully-relativistic mode supported.** The same six writers also called
  `nrelsproj()` unconditionally, so in `frl` mode `aorb_.lo[]` and
  `adat_.so[]` were never populated. The patch mirrors the branch already
  in `do_qeupf.c`: call `nrelorbnl()` for `nrl`/`srl`, `relorbnl()` for
  `frl`, and append `+`/`-` from `adat_.so[i]` to the scratch-file name.
- **Relativity-aware format selection.** OPIUM's writers refuse some
  format/relativity combinations on their own: Teter is fully-relativistic
  only, while the other eight non-UPF writers refuse fully-relativistic
  potentials. `exec_opium_formats` now drops the incompatible formats
  instead of asking OPIUM to write them and getting nothing back.
- **`opium.profile` lists all ten formats.** Default output is the nine
  formats OPIUM 4.1.0 writes for a scalar potential, plus Teter for fully-
  relativistic. The profile notes explain both the format/mode matrix and
  the upstream patch.

### Upstream

Reported as [rappegroup/opium#1][issue] and fixed in
[rappegroup/opium#2][pr]. When upstream merges, the local patch becomes a
no-op (the apply script skips any file that already uses `aorb_.lo[i]`).

[issue]: https://github.com/rappegroup/opium/issues/1
[pr]: https://github.com/rappegroup/opium/pull/2

### Store

`~/pf-native/opium` rebuilt: 297 UPF files became 1,945 files across the
ten formats, from 4 (profile x xc x rel) combinations.


## Files labelled as what they are not -- and VWN without exchange

A duplicate count, taken to size the store, found one ADPACK chlorine file
stored as PBE-full, PBE-nonrel, PBE-scalar and PBEsol-full. One file cannot be
four things. Auditing the whole store against the files' own headers:

| profile | labels built | what the files are | why |
|---|---|---|---|
| vanderbilt | pz, pbe | **PW91** | every deck sets `exfact 4` |
| gbrv | pz, pbesol, pbe | **PBE** | every deck sets `exfact 5` |
| fhi | pz, pbe | **PW-LDA** | every deck sets `iexc 8`, fhi98PP's Ceperley-Alder / Perdew-Wang |
| adpack | pz, pw, pbe, pbesol x nonrel, scalar, full | LDA or PBE, **dirac** | all 29 shipped decks are fully relativistic |
| cp2k-gth, hgh | full | the scalar tables | no relativistic variant exists here |

1,493 files in all. Each engine ran its library's fixed deck and ignored the
option; the file name was built from the option.

### PHYSICS CHANGE: VWN

Every `vwn` pseudopotential had **no exchange**. `data/xc.tsv` mapped vwn to
QE's `dft='VWN'`, and QE 7.x has no short name VWN -- `qe_dft_list.f90`
defines PZ, PW and VWN-RPA -- so the string was parsed token by token,
matched only a correlation, and left exchange unset. ld1.x wrote it into
every header: `NOX VWN NOGX NOGC`. It is why VWN built 46-65 elements where
every other functional built 88-95. Now `SLA VWN`: Slater exchange with VWN
correlation, the LDA the entry names. Si, Cu and O build good/excellent.

### Fixed

- **Profiles declare what their inputs produce.** fhi -> `pw`; gbrv -> `pbe`;
  vanderbilt -> `pw91`; adpack -> `pz pbe` x `full`; cp2k-gth, hgh -> `scalar`.
  Each carries its reason. Swapping another functional into a library's own
  deck would put the library's name on a construction it never made, so the
  declarations were corrected instead.
- **`generate` enforces them.** The wizard always filtered libraries by
  functional and relativity; the command line did not. `-p gbrv -x pz` is now
  refused with the reason.
- **Non-relativistic is not free for fixed-deck engines.** It was accepted for
  every profile as "a subset of scalar". That holds for engines that build the
  atom from the setting, not for ADPACK, GTH, USPP or fhi98PP.
- **Every output is checked against its own header** (`label_mismatch`,
  `label_verify_batch`) after generation, before any test. A disagreement fails
  the element and moves the file to `pseudos/rejected/`. Expected QE names come
  from the headers ld1.x writes, not from memory. Tested against the real store:
  all seven kinds of mislabel caught, nine correct files passed.
- **The store builder verifies before it builds.** Combinations no longer in
  the plan are pruned; every stored file is checked against its directory's
  label; failures go to `.rejected/` and their combinations are rebuilt in the
  same run.

### What the check caught on its first run

- **Every USPP-derived UPF had a meaningless `relativistic` field.** QE's
  `readvan` (upflib/read_uspp.f90) reads `irel` from the file and never uses
  it; upfconv writes whatever the structure held. Two decks with the same
  `irel = 2` came out "scalar" and "no". Now written from the deck, by
  runatom.f's own definition: 0 non-relativistic, 2 Koelling-Harmon scalar.
- **APE's files, rewritten as v2, said "no".** A v1 file has no relativistic
  field. Now written from the deck's `WaveEquation` -- schrodinger and
  scalar_rel only; a dirac run through v1 carries no spin-orbit data, and is
  left for the check to refuse.
- **The check itself read 24 columns of a v1 functional line; QE reads 20.**
  Fixed to read what QE reads.


## The native-store build: a three-hour hang, and nine impossible combinations

The first full build stopped at combination 194 of 280 for three hours. All
103 elements of that combination were built and tested; it was writing its
report. The `ld1.x` version probe in that step had started Open MPI, whose
initialisation lists network interfaces through netlink, and the process was
blocked in the kernel on `rtnl_lock` (state D). WSL's networking lock had
wedged for the whole VM -- `ip link` did not return either -- and a process in
state D ignores every signal, so `timeout 10` could not end it.

- **The version probe runs once per binary**, cached by device, inode and
  mtime, instead of on every report. It is watched rather than waited on: run
  in the background, killed and abandoned if still alive at the limit, so a
  probe stuck in the kernel cannot stop its caller. Its output goes to a file
  instead of `| grep -m1`, which closed the pipe on ld1.x mid-write.
- **The build runs each combination under a watchdog** (`COMBO_TIMEOUT`,
  default 3600 s) in its own session, polled, and killed as a group. Past the
  limit it checks whether the kernel still answers `ip link`; if not, it stops
  and says to run `wsl --shutdown`, because every later combination would hang
  the same way. It checks once before starting as well -- tested while the
  kernel was wedged: 5.4 s to a clear message, where the old code hung.
- **Nine combinations could never have built.** `gbrv` and `pseudodojo`
  declare PAW, which their libraries publish, but their engines -- USPP and
  ONCVPSP -- make only US and NC; those PAW sets came from other codes. The
  plan now checks each family against the engine registry and lists what it
  skips, as it already did for undeclared functionals.


## The rc optimiser

`pseudoforge optimise -e EL [generate options]` sweeps `--rcut-scale`, runs
`generate` once per rung into its own project directory, and picks by a stated
rule from what the pipeline already measures:

1. eligible: generated (`ok`/`ok-warn`) and transferability at least
   `--min-grade` (default `good`); `no-data` is never eligible;
2. with `--cutoff-scan`: lowest converged `ecutwfc`, ties to the better
   verdict, the smaller eigenvalue error, then the larger scale;
3. without: the largest passing scale -- the softest that still passes.

It adds no physics. On Si PBE with ONCVPSP:

| scale | verdict | max dE (Ry) | ecutwfc |
|---|---|---|---|
| 0.9 | good | 0.00234 | 21 |
| 1.0 | good | 0.00173 | 18 |
| **1.1** | good | **0.00119** | **15** |
| 1.2 | good | 0.00314 | 15 |
| 1.3 | marginal | 0.00524 | 12 |

It chose 1.1, softer and more transferable than the default radii.
`--save-recipe NAME` stores the winner; `generate --recipe NAME` reproduces it
(tested byte for byte, bar dates). Channels are scaled together and no lattice
constant is fitted; both are stated in the command's help.

`tests/test_optimise.sh`, 18 checks: the rule on eight hand-checkable tables,
six refusals, and a real sweep reproduced from its saved recipe.

### Found on the way

- `pseudoforge recipe <mistyped element>` crashed with `$1: unbound variable`:
  the error message read `$1` after the caller had shifted it away.
- `check` was an alias of both `doctor` and `validate`; `case` takes the first,
  so `validate`'s was unreachable. It is doctor's.
- Editing the `pseudoforge` script from Windows dropped its executable bit.


## Engine output checked in pw.x: APE was unusable, --rcut-scale was a false label

The rule from the conversion round -- validation checks form, physics checks
physics -- applied to what engines hand back found five more things that
shipped as "ok".

### APE: every file was unusable in Quantum ESPRESSO

The APE item was closed last round with "LDA: 7 of 7 generate". Files were
written; none could be used. Three separate faults, each measured in `pw.x`:

| fault | measured | fix |
|---|---|---|
| UPF v1 with the functional field blank | pw.x stops: `unrecognized dft` | the deck's functional written in, LDA and GGA only |
| QE 7.6 misreads APE's v1 layout | one Si pseudopotential: 645 kbar as v1, 46 kbar as v2 (ONCVPSP 25) | rewritten as v2 through `exec_upfconv`; no number changes |
| APE logs `Ghost state found`; nothing read it | bulk Si -59.73 Ry against ONCVPSP's -15.76 | retry with each channel as local; APE's own analysis decides; recorded |

Ruled out before blaming the v1 reader: V_loc units (tail -2Z/r in Rydberg),
D_ij scale (x2, x0.5 on a ghost-free file), cut-off radii, the radial grid
(PP_RAB = dr/di), the charge (4.0000). Result: APE's Si PBE -15.761 Ry against
ONCVPSP's -15.763. For meta-GGA the functional is not written in: QE's name
there is ld1's proxy parent, and "PBE" in a SCAN file would be a false label.

Two first-cut bugs in the fix, caught by running it: `ls a*.UPF a*.upf` exits
non-zero when either pattern is empty, so every ghost retry looked like it had
written nothing; and `exec_upfconv` looked for `<input>.UPF2`, while upfconv
names a `.UPF` input's output `<prefix>.UPF2`.

### --rcut-scale: applied by one engine, stamped on four

Building Si with and without `--rcut-scale 1.2` and diffing the decks: ld1
scaled; oncvpsp, opium, ape, fhi98pp, uspp and atompaw ignored it. oncvpsp,
opium, uspp and atompaw then named the unscaled result `...-rc1p2.UPF`. Now:

- **oncvpsp, opium, ape** scale the fields their decks label as radii
  (`ib_scale_rc`); a deck with no such block is an error, and an ONCVPSP
  radius beyond `rlmax` is refused rather than "fixed" by moving the grid;
- **uspp, atompaw, fhi98pp, gth, adpack** refuse the flag before anything
  runs, each with its reason. GTH has no radii; ADPACK runs published decks
  unmodified; the other three are not implemented, and say so.

### The validator

- A file naming no functional is an error: pw.x cannot use it.
- QE's 1024-character line limit applies to v2 only -- it belongs to the XML
  reader. pw.x read a v1 file with a 1,028-character PP_INFO line.
- A line long only through trailing padding is trimmed, not re-wrapped into
  numeric columns.
- NaN or Infinity in a header attribute is reported as a converter's value,
  not as "the atomic solve did not converge".

### Smaller

- `pseudoforge validate` ran the UPF checker on every format -- a `.vps` was
  "not a UPF file" -- and passed `--help` to `basename`. It dispatches by
  format now, and has a help text.
- `upf_summary` printed a built-in default cutoff as though the file had
  suggested it (`ecut~60/480` for a copper that needs 200 Ry). It prints the
  file's own number, or says there is none.

### Tests

`tests/test_engine_output.sh`, new, 31 checks: scaling on the real deck
shapes, the refusals and that no `-rc` file is written for them, the upfconv
naming, the validator rules, the validate command, and APE's Si end to end --
v2, functional named, ghost retry recorded, and (slow) pw.x within 50 mRy of
ONCVPSP; it agreed to 2.


## Conversion: "exact" is now proven with physics, and running it overturned half the registry

Four paths were carried as "registered, not demonstrated". Checking them
properly -- source and result both handed to `pw.x`, bulk-Si energies compared
-- found an unreadable file behind a path marked exact, a PseudoForge naming
bug, three paths no tool can perform, and one wrong conclusion of my own.

### Measured

Bulk Si, ecutwfc 30 / ecutrho 240 Ry, 4x4x4, `conv_thr` 1e-10. `pw.x` reads
`.van`, `.RRKJ3` and QE-XML natively, so each source is its own reference:

| path | source read natively | converted | verdict |
|---|---|---|---|
| `van -> upf` | -15.90704670 Ry | -15.90704670 Ry | exact |
| `rrkj3 -> upf` | -22.99954954 Ry | -22.99954954 Ry | exact |
| `upf -> xml` | -15.76231144 Ry | -15.76231144 Ry | exact |

Pressures agree too. `PF_SLOW_TESTS=1 tests/test_convert.sh` re-runs all three.

### Fixed

- **`van -> upf` handed out a file `pw.x` could not open.** upfconv.x writes
  `PP_QFCOEF` as one 2,496-character row; QE's XML reader stops at 1024
  (`maxline=1024`, `upflib/xmltools.f90`). A normaliser that re-wraps such
  rows already existed -- in `lib/executor.sh`, called only by the engine
  path. `pseudoforge convert` and the website's `/api/convert` went through
  `lib/convert.sh`'s own upfconv wrapper and never called it. The normaliser
  is now `upf_normalise` in `lib/upf.sh`; both wrappers call it;
  `exec_upf_normalise` remains as an alias. Two wrappers for one tool is how
  a fix lands in only one of them.
- **The UPF validator passed that file.** It now rejects any line longer than
  1024 characters, QE's own number. And NaN or Infinity in a *header
  attribute* is reported as that, not as "the atomic solve did not converge",
  which sent the diagnosis the wrong way.
- **`rrkj3 -> upf` could never work.** `upfconv -h` advertises "*.rrkj3 or
  *.RRKJ3"; `read_ps_new` compares the file-name tail with no case folding
  and matches only `.RRKJ3`, so ld1.x's lowercase output fell through to the
  old-PWSCF reader. The file is staged under the matched spelling; the bytes
  are untouched.
- **The RRKJ3 conversion carried `xmin="-Infinity"`** (RRKJ3 does not record
  its mesh origin, so upfconv computed log(0)) **and `element=""`**. The
  undefined mesh attributes are removed, not guessed -- `r1 = exp(xmin)/zmesh`
  is one equation in two unknowns. The element is taken from the RRKJ3's own
  first record, and only when it is a real element.

### Refused, with the reason from QE's source

`cpi`, `fhi` and `cpmd -> upf` were "exact", then "yes *". QE 7.x cannot do
them: `upfconv.f90` sends every file through `read_ps_new`, whose dispatch is
`.psml`, `.vdb`/`.van`, `.RRKJ3`, `.gth`, and `read_ncpp` for everything else.
There is no FHI or CPMD branch, and QE 7.6 ships no `fhi2upf.x` or
`cpmd2upf.x` -- only `casino2upf.x` and `upfconv.x`. They are `no-tool`
refusals now. Registry: **4 exact, 9 refused**, and layer 9 is called solved
because nothing in it is undemonstrated.

### Corrections

- *"No engine here writes .rrkj3 or CPMD."* Wrong. ld1.x writes the old RRKJ
  layout for any `file_pseudopw` not ending in `upf` (QE's INPUT_LD1), and
  OPIUM writes CPMD alongside UPF from one run. Both are now real fixtures.
- *"rrkj3 -> upf is 2.2 eV wrong because Q(r) loses its pseudisation."* Wrong
  on both counts. The conversion is exact; the 2.2 eV per Si cell lies between
  ld1.x's UPF and ld1.x's RRKJ3 **of the same deck**, before any conversion --
  the old layout has no l-resolved augmentation. And every run printed
  "0 coefficients", so that line explained nothing.

### Tests

`tests/test_convert.sh` 58 -> 69: a real file per path, including ld1's RRKJ3
and OPIUM's CPMD; the refusals and their QE-source reasons; the validator
against upfconv's *actual* output rather than a hand-made long line; and the
pw.x equivalence of every exact path.


## Citations: three engines resolved, and a third state for what they are

ADPACK, AtomPAW and OPIUM were "Unverified -- check the source". All three are
resolved -- and none of their authors asks for a citation anywhere
(distribution, manual, website, each read in full). Recording a method paper as
a request would put words in their mouths, so `MD_VERIFIED` gains a third
value, `no-request`, which prints *No citation request from the authors
(checked: ...). Method reference from their own documentation: ...*.

| engine | reference, and where it comes from |
|---|---|
| ADPACK | its 2.2 manual's ref. [15], for ADPACK's own contribution: Ozaki, PRB 67, 155108 (2003); Ozaki & Kino, PRB 69, 195113 (2004) |
| AtomPAW | its own paper, ABINIT's ref. [1]: Tackett, Holzwarth & Matthews, CPC 135, 329 (2001) |
| OPIUM | ref. [2] of its scientific-references page, for the `opt` scheme our decks select: Rappe *et al.*, PRB 41, 1227 (1990) |

Every DOI was resolved to its title. ADPACK's second paper is its own entry,
linked through `MD_ALSO_CITE` as GTH links Krack -- two DOIs in one field made
one broken link. The CITATION.txt footer claimed every reference was "the one
the libraries own authors ask for"; that was false for these three and is
rewritten. ADPACK's recorded URL had gone 404.


## APE: it was never the elements, it was the functional

The roadmap carried "APE — five d-shell elements fail" as open, with the cause
unestablished. The cause is established. **All seven elements generate with
LDA**; only GGA fails, and the failure is upstream's.

### Measured

`--engine ape`, `pseudoforge-auto`, 2026-09-27:

| functional | result |
|---|---|
| `-x pz` | Ti, Fe, Cu, Zn, Ag, Br, Au — **7 of 7** |
| `-x pbe` | Br, Au pass; Ti, Fe, Cu, Zn fail `3d is unbound`; Ag fails `4d is unbound` |

### It is reproducible from APE's own file

`testsuite/all_electron/02-scalar_rel.01-no_spin.inp` is APE's shipped chromium
deck. It passes as distributed with `lda_x_rel + lda_c_vwn`, and fails with
exactly `State: 3d is unbound` when the single line naming the functional is
changed to `gga_x_pbe + gga_c_pbe`. Nothing else in the file is touched.

**APE's test suite contains no GGA case at all** — every functional in it is an
`lda_*`. The combination has never been exercised upstream.

### What was ruled out first

One at a time, before attributing anything: the order of orbitals in the deck,
the empty p channel, whether the d shell is pseudised at all (it fails in the
all-electron stage, before pseudisation is reached), libxc's density threshold
from 1e-16 to 1e-6, numerical versus analytical XC derivatives, the radial mesh
extent from 15 to 140 bohr and its point count, the eigensolver tolerance, and
the SCF iteration cap. LDA succeeds in every one of those configurations and no
GGA succeeds in any.

The mechanism: `states_batch.F90` asks `wavefunctions_n_bound_states` how many
bound states an l channel holds, and that counts nodes of a trial integration
at the top of the well. Under GGA the l=2 count comes back short, an occupied d
is classified unbound, and the run aborts.

### Not patched, and why

Changing a solver's bound-state heuristic is a physics change, and there is no
reference here to verify the result against. Inventing one is what this project
refuses to do. What changed instead is that `pseudoforge` stops repeating the
engine's four words and says what they mean:

```text
State: 3d is unbound -- APE has no working GGA path for an open-d transition
metal. Its own chromium test fails the same way when only the functional is
changed. Use -x pz with APE, or --engine ld1 or oncvpsp for PBE.
```

The bromine auto-fix still does not fire here, and should not: it keys on
`multiroot_solve_system`, a failure of the Troullier-Martins construction,
while this aborts earlier in the all-electron solve. Widening that trigger
would change which shell is pseudised for elements that already work.

### Tests

`tests/test_ape_live.sh` 17 → 27. It now runs the LDA route for all seven
elements rather than only recording the PBE failures, and checks that the
roadmap names the cause, cites APE's own deck, and that the translated message
exists in `lib/executor.sh`.


## `pspconvert` does not exist, and psp8 never needed it

Three conversion paths — `psp8 → upf`, `upf → psp8`, `fhi → psp8` — were
registered as **exact**, performed by ABINIT's `pspconvert`, and reported in
`convert --list` as `AVAILABLE: no`. That column reads as *one install away*.

**There is no program called `pspconvert`.** What was checked, and found:

| Checked | Found |
|---|---|
| ABINIT 8.10.3 and 9.10.3 source trees | no such file; the `98_main` program list names no such program |
| conda-forge `abinit=8.10.2` and `abinit=10.0.3`, both installed and listed | no `pspconvert` in `bin/` |
| `abitk`, ABINIT 10's toolkit | header, k-point, crystal, band and developer tools; no pseudopotential subcommand |
| `upfconv.x -h` | `.upf`, `.vdb/.van`, `.rrkj3`, `.cpi/.fhi`, `.cpmd`, and `.gth DOES NOT WORK`. No psp8 |

### What replaces it

**psp8 is generated, not converted to.** ONCVPSP writes it natively, and the
deck builder was forcing `psfile` to `upf`, so `--format psp8` could not work:

- `ib_oncv_psfile()` in `lib/input_builder.sh` now honours the requested
  format, on the retargeted published deck and the synthesised one alike;
- ONCVPSP's `psfile` accepts **three** values, not two — its own validator
  says `psfile must == psp8 or upf or both` — so `--format upf,psp8` sets
  `both` and gets both files. It previously produced one, while
  `docs/reference/engines/oncvpsp.md` documented the combination;
- `exec_oncvpsp` returns the psp8 as a result instead of as the wreckage of a
  failed run, and names it like every other output (`Si.pbe-oncv.psp8`);
- `psp8_validate()` in `lib/upf.sh` reads the file's own header — `pspcod`,
  `zatom` against the element named in the filename, `zion`, `lmax`, the
  projector count against the channel count, the grid length — rather than
  letting psp8 fall through to the generic size-and-NaN check.

### Two kinds of refusal

The three psp8 paths are refusals now, and a refusal was one thing where it
should have been two. `CVT_REFUSAL` records which:

- **`physics`** — the target needs numbers the source does not contain.
  PAW-XML, `.vps`, GTH.
- **`no-tool`** — possible in principle, and nothing performs it. The three
  psp8 paths.

Both appear in `convert --list`, in `convert --why`, in `/api/formats`, in the
409 from `/api/convert`, and on the website, which used to tell every refused
conversion it was "not a missing feature" — true of one kind and not the other.

### A path can be registered, its tool installed, and still not work

Running every declared path against a real file turned up a second thing the
registry did not know:

```text
$ upfconv.x -u Si.cpi
read_ncpp: PP file is empty or wrong
readpp: file Si.cpi could not be read
```

`read_ncpp` is the *old PWSCF* reader — upfconv's extension dispatch never
reached its FHI branch, although `-h` lists `.cpi` among the formats it
handles. Upstream's dispatch, not ours, and the same failure `lib/executor.sh`
already recorded against the fhi98PP engine path; the conversion registry had
never been told. `cpi → upf` and `fhi → upf` now carry the measurement, and
`tests/fixtures/cpi/Si.pz-fhi98pp.cpi` reproduces it, because a refusal nobody
can reproduce is a rumour.

`rrkj3 → upf` and `cpmd → upf` are marked untried, which is a different claim
and kept as one: no engine here writes either format and no published file was
to hand.

The report distinguishes the three states — `yes`, `yes *`, `refused` — and
`docs/reference/formats.md` gained a generated **demonstrated** column.

### The 13 paths, measured

| | |
|---|---|
| run against a real file | `van → upf`, `vdb → upf`, `upf → xml` |
| registered, fails on this QE | `cpi → upf`, `fhi → upf` |
| registered, never run | `rrkj3 → upf`, `cpmd → upf` |
| refused — physics | `pawxml → upf`, `vps → upf`, `gth → upf` |
| refused — no-tool | `psp8 → upf`, `upf → psp8`, `fhi → psp8` |

### Removed

- **`cvt_run_pspconvert()`**, the `pspconvert` branches of
  `cvt_tool_available`, `cvt_tool_version` and the not-installed advice, and
  the `doctor` record that reported `pspconvert` as *optional* — all of them
  plumbing for a program that does not exist. `PSPCONVERT_BIN` is gone with
  them and is **not** documented as a setting: an environment variable
  pointing at a nonexistent binary is worse than no variable at all.
- **`cmd_doctor_families()`** in `lib/cli.sh` — dead since `doctor` was split
  into records and renderers. Nothing in `lib/`, `tools/`, `tests/`, `server/`
  or `frontend/` called it.
- `psp8` from the `convert --to` usage line, which offered a target that is
  now refused.

### Fixed

- **`vdb → upf` was registered and unreachable.** `cvt_detect` folded `.vdb`
  into `van`, so the key the dispatcher looked up was always `van:upf`. The
  entry was real and dead. The detector now reports which of the two it saw,
  and the provenance records `source.format=vdb` instead of `van`.

### Tests

`tests/test_convert.sh` 35 → 58: one real file per declared path, the
exact/refused split, the refusal kinds, both psp8 generation routes, and a
regression that fails if `pspconvert` returns as live code.

`tests/test_roadmap.sh` 13 → 16, each check verified against the bug it exists
to catch by reintroducing the bug: a wrong exact/refused split, `pspconvert`
presented as an install away, and layer 9 called *solved* while four paths have
never been run.


## The roadmap was wrong, and so was an engine status

A stale roadmap reported format conversion as **not started** while
`lib/convert.sh` had thirteen working paths and thirty-five tests. Chasing that
turned up three more wrong claims on the same page and one wrong claim about an
engine.

### What was wrong

`docs/contributing/roadmap.md` was moved into the Diataxis tree during the
documentation pass and **never audited against the code**. Every other document
gained an anti-drift check -- generated flag tables, resolved links, parsed
commands -- and a status table got none, so it rotted quietly:

- format conversion: **"not started"**, with 13 registered paths (10 exact,
  3 refused with reasons) and a `.provenance` sidecar per conversion;
- core-hole: **"not yet exposed"**, with `--core-hole`, a refusal for shells
  the element lacks, and a tutorial;
- **"Eight"** engines, with nine registered;
- the website and the ADPACK integration listed as outstanding, both done.

### And the one that mattered more

**APE was reported as passing all seven previously-failing elements. It passes
two.** Measured: Br and Au generate; Ti, Fe, Cu and Zn fail with
`State: 3d is unbound`, Ag with `State: 4d is unbound`, under both
`pseudoforge-auto` and `psl-high`.

The bromine auto-fix keys on `multiroot_solve_system` and does not fire here --
the state file records `attempts: 0`, because an unbound *occupied* d shell is
a different failure from the empty-shell problem fixed earlier.

The reason it went unnoticed is worth stating plainly: **`tests/test_ape.sh`
checks deck construction, not generation.** It says so in its own header and
runs without APE installed. Thirty-one passing checks said the deck was built
correctly; they never said APE accepted it, and the difference was not noticed.

The trigger has deliberately **not** been widened to catch the unbound case.
That would change which shell is pseudised for elements that never asked for
it, which is a physics change and not one to make on a guess.

### Added

- **`tests/test_roadmap.sh`** (13 checks) -- the roadmap's claims against the
  code: nothing called unbuilt that is built, nothing called solved without
  something that proves it, engine and interface counts from the registry, and
  open items that cannot quietly disappear.
- **`tests/test_ape_live.sh`** (17 checks) -- runs APE and compares the result
  against the recorded status, so the claim and the measurement are the same
  thing. It also fails if an element *starts* working without the record being
  updated, since that is how the last one rotted.

### Fixed

- `roadmap.md` rewritten against measured reality, with each open item carrying
  what was measured and when.
- `reference/engines/ape.md` states the five failing elements, the error each
  gives, and why the bromine fallback does not apply.
- **The roadmap test contained the very bug it exists to catch.** Its
  unverified-citation count piped into `grep -q`, which closes the pipe on the
  first match; `pseudoforge` died of SIGPIPE and `pipefail` turned the whole
  pipeline into a failure, so all three unverified citations counted as
  verified. It captures the output first now.


## Engine citations

The five engines carrying `Unverified -- check the source` were chased through
the source distributions on disk. **Two resolved from the authors' own words,
one was already in the codebase under another id, and two genuinely ship no
citation.**

### Resolved

**APE** -- `README.md` in the APE source tree has a heading *"How to cite
APE"*. Oliveira and Nogueira, *Comput. Phys. Commun.* **178**, 524 (2008),
DOI 10.1016/j.cpc.2007.11.003.

**GTH** -- every GTH data file under
`cp2k-data/potentials/Goedecker/` carries a `Please cite:` block naming three
papers: Goedecker/Teter/Hutter (1996), Hartwigsen/Goedecker/Hutter (1998) and
Krack (2005).

The GTH case is the interesting one: **that citation was already here**,
verified, under the `cp2k-gth` profile id, complete with all three
cross-references and a note on when to cite which. The engine id `gth` simply
had no entry, so `pseudoforge citation` fell through to "Unverified" for a
reference the codebase already held. It is now aliased, the way `ld1` aliases
`quantum-espresso`.

### Not resolved, with a named next step

Three distributions ask for no citation at all. The placeholder stays, and each
now carries a TODO naming what to check:

**AtomPAW** -- `README`, `README.md` and `AUTHORS` name N. A. W. Holzwarth and
M. Torrent and point at the project site, but request nothing.
*TODO: read `doc/atompaw-usersguide.pdf`, or http://users.wfu.edu/natalie/papers/pwpaw.*

**ADPACK** -- `adpack2.2` ships only `source/` and `work*/`. No README, no
`doc/`, no citation request; the sources carry
`Copyright (C) 2002-2007, Taisuke Ozaki` and a GPL notice.
*TODO: check http://www.openmx-square.org/adpack/adpack.html.*

**OPIUM** -- `README`, `INSTALL`, `COPYING` and four files in `doc/`, none of
which asks for a reference.
*TODO: check http://opium.sourceforge.net, which the README names as where
further information lives.*

### Changed

- **`MD_CITE_SOURCE`** records where a citation was taken from, so a claim can
  be rechecked without repeating the search through someone else's tree. It is
  printed with the citation.
- **`MD_CITE_TODO`** replaces a bare "Unverified" with a named next step. A
  TODO that names a file is a checklist item; a bare "Unverified" is a mystery,
  and mysteries do not get resolved.
- **`MD_ALSO_CITE` was dead data.** It was populated for eight entries and read
  by `md_citation_set` only -- so `pseudoforge citation --all` printed one of
  GTH's three papers and silently dropped the other two. The listing now
  expands it.
- `docs/contributing/adding-an-engine.md` gains the rule: **before you merge an
  engine, find its citation; check the tarball; if there isn't one, say so
  explicitly** -- with where authors actually put them (a heading in APE's
  README, a block inside every GTH *data file*), and the instruction to check
  whether the reference is already in the file under another id.


## The website -- a fourth interface

A REST API, a static frontend, the documentation served from the same domain,
and the deployment for a 1-core VPS. 763 tests pass, 0 fail.

### It is an interface, not a project

`lib/http.sh` **is** the API: the route table, the handlers, the response
shapes and the refusals, in Bash, with the rest of the core. The HTTP server is
a transport:

    HTTP request  ->  pseudoforge api <METHOD> <PATH> [body]  ->  HTTP response

`server/app.py` moves bytes and a status code. Tests assert it has no logic of
its own: that it never decides about conversion kinds, and that every endpoint
goes through `call_core`. `GET /api/health` is checked to return the *same
record count* as `pseudoforge doctor --json`, because a divergence there would
mean the endpoint had started doing its own checking.

The route table also generates `docs/reference/http-api.md` and answers
`GET /api/routes`. One table, three consumers.

### The VPS does not run engines

1 core, 1 GB, 10 GB of disk. No engines, no Quantum ESPRESSO, no GSL, LAPACK,
cmake or ninja. `POST /api/generate` answers **501** with instructions for
running it locally.

That is the honest answer, not a limitation worked around: a queue whose
workers do not exist looks like it is working, and the user waits for something
that never arrives. The queue-and-worker model is documented in
`docs/architecture/http.md` as a possible extension, with the reason it is not
implemented -- there is no worker that reliably exists yet.

`tests/test_vps_layout.sh` asserts the 8 GB budget **and** that the installer
pulls in no compiler and builds no engine. The first symptom of that having
changed, on a live machine, is a full disk.

### Added

- **`lib/http.sh`** -- 13 endpoints, the route table, and the refusals.
- **`pseudoforge api`** and **`pseudoforge native index|list|size`**.
- **`server/`** -- FastAPI transport, cache-warming worker, SQLite migration.
  Python is an external dependency of the same kind as gnuplot: nothing in
  `lib/` imports it.
- **`frontend/`** -- four static pages, no framework, no build step. The
  periodic table, the six selectors and the download browser are all filled
  from the API, so none of them can go stale.
- **`deploy/`** -- an idempotent installer, Nginx with `/api/`, `/docs/` and
  `/library/` ordered before the catch-all, hardened systemd units,
  `upload-native.sh`, `update-docs.sh`, `load-index.sh`, and a gitignored
  `deploy/local/`.
- **Tests**: `test_http.sh` (64), `test_vps_layout.sh` (14),
  `test_nginx_config.sh` (20), `test_docs_deploy.sh` (12).

### Fixed -- found by building it

- **`HTTP_STATUS` never escaped its subshell.** `cmd_api` captured the handler
  with `$(...)`, so every response was 200 -- including every refusal. The one
  that mattered: `POST /api/generate` returned 501 from the handler and 200 to
  the caller.
- **The native index indexed its own temporary file**, and took the format from
  the file extension (`UPF`) rather than the registry id (`upf`), so every
  conversion reported "no such path". It now uses `cvt_detect`, which is what
  the converter uses and which tells PAW-XML from XML by content.
- **The convert handler re-implemented the core's decisions** -- the refusal
  check, the tool check -- and passed `cvt_convert` a file path where it wanted
  an output directory. The result was a *directory* that passed a `-s` test and
  was reported as a successful 80-byte conversion. It now delegates and
  captures the path `cvt_convert` prints.
- **A cached conversion could not be downloaded.** Its id contains a slash
  (`<source>/<name>`) and the router rejected any parameter with one. Routes can
  now declare a rest-parameter, and `:id` still refuses a slash so a path cannot
  be smuggled through an id.

### Documentation

`docs/index.md` rewritten as a landing page: what it is, what it does, why it
exists, one command with its output, and three ways on. Plus
`architecture/http.md`, `reference/http-api.md`, `how-to/deploy.md`,
`how-to/use-the-website.md` and `contributing/writing-docs.md`.

The site is built for the `/docs/` prefix and served from the same Nginx config
as the application. `tests/test_docs_deploy.sh` checks **3,770 links in the
built HTML** -- not in the Markdown -- because an absolute link works in
`mkdocs serve` and 404s on the deployment, which is the worst kind of bug.
Every engine page now links to `/api/engines/:name`, and formats and profiles
to their endpoints.


## Documentation

51 pages, Diataxis-structured, built with MkDocs Material. `mkdocs build
--strict` passes with zero warnings; MkDocs remains **optional** -- the pages
are Markdown and read fine in the repository.

### Verified rather than reviewed

The point of the pass was not prose. Documentation rots by one flag being
renamed while the text stays as it was, so the checks came first and the pages
were written against them.

- **`tests/test_docs.sh`** (13 checks) extracts every `pseudoforge` command
  from every fenced block -- 175 of them across 51 pages -- and checks the verb
  exists and every flag is one the parsers accept. Under `PF_SLOW_TESTS=1` it
  runs each tutorial's generate command and requires the documented output.
- **`tools/gen_reference.sh`** generates the command, engine, format and
  profile tables *from the parsers and registries themselves*, and the suite
  fails when what is committed is not what the code would produce today. 131
  flags are now documented, up from a hand-written subset.
- **`tests/test_mkdocs.sh`** (9 checks) runs `mkdocs build --strict`.

A tutorial that deliberately shows a refused command marks it
`# expect: refused`, and the refusal is asserted rather than skipped: a refusal
that stopped happening would be a silent behaviour change.

### Seven tutorials, with real transcripts

Carbon, silicon, iron, copper (core hole), gold (fully relativistic, ONCVPSP),
r2SCAN (AtomPAW), and a 29-element batch. Every transcript was captured from a
real run. Where something is refused, warns, or returns no data, that is shown
-- a tutorial that only demonstrates the happy path teaches nothing about the
day it does not happen.

### Fixed -- found by writing the documentation

Eight defects, none of them in the prose:

- **`cmd_citation` listed four engines out of nine.** Anyone publishing work
  made with APE, ADPACK, AtomPAW, OPIUM or GTH was never told to cite them. Now
  read from the registry via a new `eng_list`.
- **The `--engine` help text listed the same four.** Same fix.
- **An auto-fix never reached `PROVENANCE.txt`.** The writer grepped for a
  phrase the auto-fix engine had stopped using, so a run that widened copper's
  radii by 12% reported it on the console and recorded nothing in the file
  meant to outlive the console.
- **A core hole in a shell the element does not have produced a file anyway**,
  tagged `-ch5f`, reported `ok`, with no core hole in it. Now refused -- and
  two callers of `recipe_apply` were discarding its return value.
- **AtomPAW meta-GGA with a relativistic solver** failed with
  `no convergence in boundsr`. Its meta-GGA path is non-relativistic only; now
  refused before anything runs, with both ways out. Not switched silently:
  relativity is physics.
- **The functional note contradicted itself.** An AtomPAW r2SCAN run printed
  "generated natively by AtomPAW" and then "was not generated self-consistently
  with R2SCAN". It keyed off the functional registry instead of asking whether
  the functional actually used differed from the one requested.
- **`--rho0`, `--from` and `--tag-suffix`.** The first was implemented and
  reachable from nothing (now a flag); the other two were invented by the docs
  and did not exist (now corrected -- `convert` takes `<file> --to <format>`).
- **The wizard's help opened five documents by their old paths** after the
  reorganisation. `tests/test_ui.sh` now reads the targets out of `tui_help`
  itself, so moving a page cannot leave the wizard pointing at nothing.

### Structure

`docs/` reorganised into Diataxis quadrants. The nine existing documents were
moved rather than rewritten -- 2,186 lines of vetted prose kept -- and every
reference to them updated in `lib/`, `tests/`, `README.md` and `CHANGELOG.md`.

One page per engine, each covering what it produces, its native format and what
it converts to, its parameters, its known limitations, the auto-fix strategies
that apply to it, how to build it, and how to cite it.

### Known gap

**Five of the nine engines carry `Unverified -- check the source` citations**:
ADPACK, APE, AtomPAW, GTH and OPIUM. The engine pages say so rather than
filling the space from memory. These should be confirmed from each
distribution's own documentation before publication.


## Plots

`--plot` on a run, or `pseudoforge plot <project>` on a finished one. Rendered
by gnuplot if it is on PATH, else matplotlib through python3, else not at all
-- with a line saying so and exit 0, because a machine without a plotting
program has not produced bad pseudopotentials.

python3 here is an external renderer reached through PATH, exactly as gnuplot
is. Nothing in `lib/` depends on it, and with both backends absent every other
feature behaves identically.

### What can be drawn, and what cannot

| plot | data |
|---|---|
| log derivatives, AE vs PS | produced by PseudoForge under `--plot` |
| radial wavefunctions, AE vs PS | already produced by every run |
| band structure | **not computed here** -- reads `bands.x` output |
| density of states | **not computed here** -- reads `dos.x` output |

Generating a pseudopotential does not involve a crystal. Producing a band
structure would mean inventing a structure, a k-path and a cutoff on the
user's behalf and labelling the result as theirs. So those two plotters read
the output of the QE tools that do compute them, and with no such output
`--plot` names the command that would produce it instead of drawing nothing
and saying nothing.

### Log derivatives, and where the keywords go

ld1.x writes `ld1N.dlog` and `ld1Nps.dlog` when given `rlderiv`, `eminld`,
`emaxld`, `deld` and `nld`. Three details, each established by testing rather
than assumed:

- They belong in **`&input`**, not `&inputp` and not `&test`; the first two
  guesses were both rejected by ld1.x.
- `file_logder` is an `&inputp` keyword and is *rejected* in `&input`. With
  none given, ld1.x writes the default names anyway.
- They go into the **validation** deck (`iswitch=2`), which runs after the UPF
  has been written, so they cannot affect the pseudopotential -- and the
  generation deck stays byte-identical to PSlibrary's.

Measured on Si, Fe and O, with and without `--plot`: the UPFs, the
transferability verdicts and the generation decks are bit-identical. The only
difference is the five keywords in the validation deck.

`rlderiv` has to sit outside the matching region or the curve shows the
pseudisation rather than the scattering, so it is derived from the largest
`rcut`/`rcutus` in the recipe's own card block plus 0.3 bohr (2.50 if no deck
can be read). `--plot-rlderiv` overrides it.

### Added

- `--plot`, `--no-plot`, `--plot-dir`, `--plot-format`, `--plot-bands`,
  `--plot-dos`, `--plot-rlderiv`; the `plot` verb; a `plotting` row in doctor,
  reported as *optional* and never as *missing*.
- `lib/plot.sh`. Both backends render from one description -- a TSV whose
  first line names the columns -- so they cannot drift into drawing different
  pictures from the same data.
- `tests/test_plot.sh` (33 checks) and `tests/mock/gnuplot`, which validates
  the script it is handed and writes the file that script promised. What
  gnuplot does with a valid script is gnuplot's business; that we hand it a
  valid one is ours.

### Fixed while looking at the output

Three defects that only a rendered picture shows, all found by looking at the
PNGs rather than at the code:

- **The wavefunction plot labelled every curve wrongly.** The AE and PS files
  do not have the same number of orbitals -- the pseudo atom has fewer, which
  is the point of it -- and folding them as though they matched put the pseudo
  file's `r` column in as a data series and shifted every label after it onto
  the wrong curve. The header is now read from each file on its own terms.
- **One pole flattened the whole log-derivative plot.** Every channel has a
  pole where it crosses a bound state; at 500 units tall it left six curves
  looking like a straight line. The y-axis is clipped to the bulk of the data,
  so the poles read as spikes leaving the frame -- how these plots are
  normally shown -- and the AE/PS agreement the plot exists to show is visible.
- **The wavefunction plot ran to 100 bohr** of flat line. It is cut to where
  the last curve stops being distinguishable from zero.


## Saved recipes

`pseudoforge recipe save <name>` keeps a run's settings; `pseudoforge generate
--recipe <name>` runs them again. The property under test is that the second
command produces the same pseudopotentials as the first, byte for byte, decks
included.

### Added

- **`pseudoforge recipe save|load|show|list|delete|export|import|path`.**
  `recipe <element>` still prints the ld1.x deck for an element, as it always
  has; no subcommand name is an element symbol, and a test asserts it.
- **`--recipe NAME` on `generate`.** Applied in a pre-pass, before any other
  flag is parsed, so position does not change meaning: an explicit flag wins
  wherever it sits in the argument list. `-e` *replaces* a recipe's element
  list rather than appending to it -- `--recipe r -e Fe` generating Fe, Co and
  Ni because the recipe named three is not "an explicit flag wins". Several
  `-e` on one line still accumulate, as before.
- **`--rho0`.** `SPEC[rho0]` was implemented in `recipe_apply` and reachable
  from nothing. The table check below is what found it. Its default is
  unchanged (unset), so no existing run generates anything different.
- **`tests/test_recipe_roundtrip.sh`** — 39 checks.

### The format

Plain `key=value`, readable and diffable. A recipe carries the specification,
the element list, and the run options that change the result (`--no-test`, the
cutoff scan, the auto-fix budget). Deliberately **not** the output directory —
where, not what — nor the worker count, which `tests/test_batch_isolation.sh`
shows makes no difference to the output.

Recipes are meant to be shared, so a recipe from someone else is untrusted
input. It is **parsed, never sourced**: a `$(...)` in a value is stored as the
literal text it is, and a test writes a recipe containing a command
substitution and asserts nothing runs. An unrecognised key is refused rather
than skipped — a key that is silently dropped is a recipe that generates
something other than what it says.

### Fixed — two interfaces, two formats, one broken promise

The wizard's review screen has offered *"Save these choices as a recipe"* for
some time, telling the user to reload it with
`pseudoforge generate --recipe <name>`. It wrote a bare command line, into a
directory named by a variable of its own (`PF_RECIPE_DIR`), in a format no
loader could read — and **the flag did not exist**. All three are fixed:
`tui_save_recipe` now writes through `rcp_save`, both interfaces resolve the
directory the same way, and the wizard can load a recipe back (main menu,
*"Start from a recipe saved earlier"*).

### Fixed — found by writing the round-trip test

- **`SPEC[engine]` and `SPEC[source]` were never declared in `spec_init`.** The
  loader rejected the very keys `rcp_save` had just written.
- **`cli_check_spec` assigned `SPEC[engine]=${CLI_ENGINE:-}` unconditionally**,
  discarding a loaded recipe's engine without a word. It now falls back to the
  loaded value before deriving one — the pattern `SPEC[source]` already used.

### Changed — one implementation of the command line

`ui_cmdline` built the equivalent `generate` command inside the TUI module.
It is now `spec_cmdline` in `recipe.sh`, and `ui_cmdline` delegates, so the
command the review screen shows, the command `recipe load` prints, and the
command that reproduces a run are the same string by construction.

`SPEC_FLAG` maps each specification key onto the flag that sets it. A key
present in `SPEC` but in none of the tables fails the suite, which is how
`--rho0` surfaced: without the table it would have round-tripped through the
file and silently vanished from every command line shown to a user.


## Caesium, and the corrections that could not survive their own extractor

Caesium was the one element that failed the 52-element `psl-low`/US batch:

    Cs   ERROR: implausible z_valence=-5.0000000000000000

### The defect

Upstream PSlibrary 1.0.0 generates Cs from

    config='[Xe] 4f14 6s1 6p0 5d0'

`[Xe]` is 54 electrons and does not contain 4f — 4f first fills at Z=58 — so
that line asks for 68 electrons in an atom with Z=55. `ld1.x` counts a core of
60, reports `z_valence = 55 − 60 = −5`, writes the UPF, and **exits 0**. The
same config appears in `us_ps_low.job` and `paw_ps_low.job`.

Measured against QE 7.6 `ld1.x`, the upstream deck gives `z_valence = −5.00`,
47 SCF iterations and `warning: at least one error in KS equations`. All three
match the signature recorded in the failing batch, which is what identifies
this as the cause rather than a plausible story about it.

### The correction

One token, `4f14` → `4f-1` — ld1's marker for an unoccupied channel, and what
upstream itself writes for Cs in the high set. Measured: `z_valence = 9.00`
(5s² 5p⁶ 6s¹), 27 iterations, no warning, AE−PS eigenvalue agreement within
1×10⁻⁵ Ry, transferability **excellent** in both US and PAW. The 4f channel is
unoccupied and absent from the pseudo-wavefunction list, so the corrected deck
is bit-for-bit identical to dropping 4f altogether.

**This is a physics-input change, not a build fix.** It changes the
all-electron reference configuration a recipe is generated from. It is admitted
here, in `data/psl/ERRATA.tsv`, and in the `recipe.erratum` lines of every
`PROVENANCE.txt` produced from a corrected recipe.

### The real bug

The correction had already been made once — by hand, directly on the extracted
template, with no test and no changelog entry. `tools/extract_pslibrary.sh`
begins with `rm -rf "$OUT"`, so the next extraction would have silently
reverted it. Diffing the shipped tree against a fresh extraction found exactly
two hand-edits across 1,040 templates, both of them this correction, and nothing
recording that they existed.

So the fix is not the token:

- **`data/psl/ERRATA.tsv`** — declared corrections: the set, element, variant,
  keyword, the exact upstream text, the replacement, and the reason with the
  measurement behind it. A row is admissible only where upstream is
  *impossible*, not merely unusual.
- **`tools/extract_pslibrary.sh`** — copies the errata out before the wipe,
  reapplies them on every extraction, and fails if an upstream text no longer
  matches (upstream changed; recheck the claim) or if a rewrite does not take.
  The splice is literal: `sub()` would read `[Xe]` as a character class, not
  match, and report success — which is how the first version of this patch
  silently did nothing.
- **`check_configs`** — extraction now refuses to ship any generation deck
  (`iswitch=3`) whose config asks for more electrons than the nucleus has.
  This caught the second instance, `paw-low/Cs`, that the manual pass had
  missed. Negative occupations mark unoccupied channels and count as zero.
  Test decks (`iswitch=2`) are exempt: a charged reference configuration is a
  legitimate transferability probe and upstream ships several.

### Changed

- `lib/profiles.sh` — `psl_erratum` exposes the declarations to any interface.
- `lib/report.sh` — `PROVENANCE.txt` gains `recipe.erratum` and
  `recipe.erratum.reason` when a run used a corrected recipe. A run that used
  none says nothing.
- `tests/test_psl_roundtrip.sh` — the claim was "byte-identical to upstream",
  which the hand-edit had already quietly falsified. It is now the stronger and
  checkable "identical to upstream except exactly where `ERRATA.tsv` declares
  otherwise": an undeclared difference fails.

### Added

- `tests/test_cs.sh` — 33 checks. The erratum is declared with the exact
  upstream text; the shipped recipe carries the correction; the extractor
  reapplies it literally; no generation deck anywhere overfills its nucleus;
  provenance names it; upstream still has the defect the erratum claims to
  correct. Under `PF_SLOW_TESTS=1` it generates Cs in both families and asserts
  `z_valence = 9`, status ok and transferability at least *good*. Verified to
  fail — three checks — when the recipe is reverted.
- `tests/test_batch_isolation.sh` — 15 checks. Batch isolation was the first
  suspect and turned out to be innocent, but nothing was testing it. Each
  element gets its own scratch directory (ld1.x writes fixed-name scratch
  files), state is sharded per element, a failure is confined to its own
  element, and merge order does not leak into the state file. Under
  `PF_SLOW_TESTS=1` the same batch is run at `-j 1` and `-j 8` and every
  pseudopotential must be byte-identical.

### Not changed

`data/psl/tests/paw-high/La.spfn.1.0.0.tpl` carries `[Xe] 4f0 5d1.0 6s2 6p1`,
58 electrons for Z=57. It is faithful to upstream and it is a *test* deck, where
a charged configuration is a legitimate probe. Flagged here rather than
corrected: inventing a parameter to tidy a number would be worse than the
oddity.


## Full-tree audit (v1.0 pre-release)

A call-graph pass over 488 functions in `lib/`, plus a consistency pass over
`data/`, `tests/` and `docs/`. Zero duplicated function definitions were found.

### Removed — dead code, no caller anywhere in the tree

- `fmt_opium_keywords` (formats.sh) — superseded by `exec_opium_formats`, which
  reads the same registry and is the one the executor calls.
- `gth_table_elements`, `gth_input_elements` (gth.sh) — coverage helpers written
  during the GTH work and never wired to anything; `prof_covered_elements`
  answers the same question through `params_find`.
- `ib_adpack_eq` (input_builder.sh) — orphaned when relativity retargeting was
  removed from the ADPACK builder. `eq.type` is read from the deck now, because
  rewriting it breaks the coupled `<log.deri.R>` block.
- `nml_has` (namelist.sh) — a one-line wrapper over `nml_get`; every caller used
  `nml_get` directly.
- `prof_coverage` (profiles.sh) — superseded by `prof_coverage_count`, which
  counts real per-element coverage rather than PSlibrary set size.
- `recipe_variants` (recipe.sh) — superseded by `recipe_select`.
- `spec_get`, `spec_set` (recipe.sh) — trivial accessors; the code reads and
  writes `SPEC[...]` directly throughout.
- `ui_elements_review` (ui.sh) — superseded by `ui_review_elements`, which shows
  coverage against the chosen settings rather than against one PSlibrary set.
- `ui_gauge` (ui.sh) — an unused whiptail progress helper. The TUI rebuild will
  provide progress bars against its own screens; keeping a helper nothing calls
  would have meant maintaining an untested one.

### Fixed — a missing call, not dead code

- `ib_oncv_xc_warn` was defined and **never called**. It is the warning that
  fires when ONCVPSP cannot produce the requested functional, so a run asking
  for PBEsol against a stub-linked build produced PBE with nothing said. Now
  called from `ib_build_oncvpsp`. This is a behaviour fix, not a cleanup.

### Fixed — provenance and drift

- `data/params/gipaw/` had no `SOURCE.txt`; every other bundled parameter set
  had one. Added, recording the upstream repository, what the 17 decks are, and
  that they are unmodified.
- `README.md` and `docs/explanation/physics.md` both said PseudoForge "drives four atomic
  codes". It drives nine. README now carries the engine table.
- `README.md` advertised "88 checks"; the suite is 159 in that file alone.
- `docs/contributing/roadmap.md` said 317 checks across eight suites; it is 428 across
  thirteen.

### Checked and found clean

- No duplicated function definitions across modules.
- No test references a removed function.
- Every CLI command is mentioned in at least one test suite.
- Every `data/params/` directory documents its origin.
- Every profile's `engine=` names a registered engine.
- Every `xc.tsv` proxy target exists; every `formats.tsv` engine is registered.
- No `.bak`, `.orig` or `.rej` files anywhere in the tree.


## 1.0.0

First release.

### Generation
- Complete PSlibrary 1.0.0 recipe database: 567 generation recipes and 462
  transferability test decks across 11 sets (`paw-high`, `us-high`, `paw-low`,
  `us-low`, `nc`, the 0.3.1 collection, and the `alt`/`tot` variants),
  extracted mechanically from the upstream `.job` files.
- An untouched run reproduces the upstream `ld1.x` deck byte for byte, verified
  on every test run by `tests/test_psl_roundtrip.sh`.
- Relativity-conditional recipes and per-set `frozen_core` defaults are
  preserved and selected automatically.
- NC, US and PAW; scalar-, full- and non-relativistic.
- Norm-conserving in both the separable Kleinman–Bylander form (`pseudotype=2`,
  the default) and the ghost-free semilocal form (`pseudotype=1`), via
  `--nc-form semilocal`.
- 33 exchange-correlation functionals. LDA and GGA are generated natively;
  meta-GGA, hybrid and van der Waals functionals are generated with their
  accepted semilocal parent, and the substitution is recorded in the log, the
  report and the run manifest.
- `pseudoforge-auto` builds recipes for elements no shipped library covers, by
  adapting a neighbour's recipe and scaling cut-off radii by the ratio of
  covalent radii. Always labelled as a heuristic; validation is forced on.

### Physics controls
- Atomic configuration, core holes (XPS/XAS), fractional nuclear charge
  (virtual crystal), explicit `zval`.
- NLCC with `rcore`/`rho0`; augmentation functions (AE, PSQ, Bessel, Gaussian,
  Blöchl-Gaussian) with matching radius; local channel `lloc`/`rcloc`.
- Extra projectors per channel; global cut-off radius scaling.
- Radial grid (`xmin`, `dx`, `rmax`) and SCF controls (`beta`, `tr2`).
- Spin-polarised generation; GIPAW reconstruction for NMR/EPR.
- UPF v1 and UPF v2 output.
- Any change that alters what the pseudopotential *is* automatically tags the
  file name, so a modified pseudopotential can never be confused with the stock
  library one.

### Execution
- Parallel generation across `MAX_PARALLEL_JOBS` elements.
- Per-element failure isolation: a failing element never stops the batch.
- Resume: a re-run skips elements whose UPF is present and validated.
- Auto-fix engine that classifies `ld1.x` failures by the routine that raised
  them and retries with a targeted, documented relaxation. The strategy that
  worked is recorded.

### Validation and reporting
- Structural UPF checks (truncation, NaN/Inf, Fortran overflow markers, missing
  data blocks, implausible `z_valence`) for both UPF v1 and v2.
- `ld1.x` transferability tests, graded excellent / good / marginal / poor.
- `pw.x` kinetic-energy cutoff convergence scan, on a generic fcc cell or on
  your own structure via `--pw-template`.
- `summary.txt`, `summary.csv`, `summary.json` and a self-contained,
  theme-aware `summary.html`.
- A run manifest recording every setting, the resolved functional and its
  provenance, and the `ld1.x` version.

### Interfaces
- A whiptail TUI: five-step wizard, advanced physics screen, recipe and profile
  browsers, validation, import, settings, and a review screen that prints the
  equivalent command line.
- A complete non-interactive CLI covering everything the TUI can do.
- Element selection by symbol, name, atomic number, range, block, series,
  period, group, named preset, or exclusion.

### Third-party libraries
- SSSP, GBRV, SG15, PseudoDojo, HGH, Vanderbilt, FHI, Wentzcovitch/VLab and
  Dacapo/CAMPOS are registered as import-only, with attribution, generating
  code and the reason `ld1.x` cannot reproduce them. `pseudoforge import` runs the
  full validation and reporting pipeline over published files.

### Tests
- 96 checks against mock `ld1.x`, `pw.x` and `whiptail`, needing no Quantum
  ESPRESSO build.
- Full PSlibrary round-trip verification.
