# Command line reference

Everything `pseudoforge` accepts. The tables below are **generated from the
parsers themselves** by `tools/gen_reference.sh`, and `tests/test_docs.sh`
fails if what is committed here is not what the code would produce today. A
flag cannot be added, renamed or removed without this page noticing.

```bash
pseudoforge <command> [options]
```

With no command and a terminal attached, PseudoForge starts the guided wizard.
With options but no command, it generates:

```bash
pseudoforge -e Si -t paw -p psl-high -x pbe
```

is the same as `pseudoforge generate -e Si …`.

<!-- generated:begin -->
<!-- Do not edit between these markers: tools/gen_reference.sh writes them. -->

### Commands

| Command | Arguments | What it does |
|---|---|---|
| `wizard` | -- | guided flow, straight to the first layer |
| `tui` | -- | the full menu (guided, quick, browse, settings) |
| `engines` | `<sub>` | list \| build <name>\|all \| show <name> \| path <name> |
| `generate` | -- | generate pseudopotentials |
| `validate` | `<file>...` | structural check of existing files (any format) |
| `convert` | `<file> --to F` | convert between formats (--list shows the paths) |
| `import` | `<dir>` | register third-party UPFs into a project and test them |
| `native` | `<sub>` | index \| list \| size [dir] |
| `report` | `[project]` | rebuild the reports of an existing project |
| `list` | `<what>` | profiles \| functionals \| elements \| recipes \| sets |
| `show` | `<profile>` | full description of a library profile |
| `recipe` | `<element>` | print the ld1.x deck that would be generated |
| `recipe` | `save <name>` | save the current settings as a named recipe |
| `recipe` | `load <name>` | show the command a saved recipe is equivalent to |
| `recipe` | `list` | list saved recipes |
| `recipe` | `export <name>` | write a recipe out to share it |
| `recipe` | `import <file>` | take one in |
| `compare` | `<a> <b>` | compare two pseudopotentials side by side |
| `citation` | `<library>` | the citations for a library (--all for every one) |
| `params` | `<sub>` | status \| fetch \| path \| extract (library inputs) |
| `profile` | `<sub>` | list \| new \| edit \| remove (library profiles) |
| `xc` | `<sub>` | list \| add \| remove (functionals) |
| `api` | `<method> <path>` | call the local API server (api --routes lists them) |
| `optimise` | `-e EL [opts]` | sweep --rcut-scale and pick the softest radii that |
| `plot` | `<project>` | draw log derivatives and wavefunctions for a run |
| `doctor` | -- | check the environment and the recipe database |
| `advise` | `-e EL [opts]` | physics reasoning on which pseudopotential to choose |
| `provenance` | `<id>` | show provenance record for a native file |
| `element` | `<symbol>` | list native store files and missing profiles for an element |
| `coverage` | `[--profile P]` | matrix of element x profile availability |
| `recent` | `[--count N]` | show most recently added files to the store |

### Options

| Flag | Takes a value | Sets |
|---|---|---|
| `-e`, `--elements` | yes | `CLI_ELEMENTS` |
| `-t`, `--family`, `--type` | yes | `SPEC[family]` |
| `-p`, `--profile` | yes | `SPEC[profile]` |
| `-x`, `--xc`, `--functional` | yes | `SPEC[xc]` |
| `-r`, `--rel`, `--relativity` | yes | `SPEC[rel]` |
| `--recipe` | yes | `--` |
| `--variant` | yes | `SPEC[variant]` |
| `--upf` | yes | `SPEC[upf]` |
| `-o`, `--output` | yes | `CLI_OUTPUT` |
| `-j`, `--jobs` | yes | `MAX_PARALLEL_JOBS` |
| `--author` | yes | `SPEC[author]` |
| `--config` | yes | `SPEC[config]` |
| `--core-hole` | yes | `SPEC[core_hole]` |
| `--zed` | yes | `SPEC[zed]` |
| `--zval` | yes | `SPEC[zval]` |
| `--nlcc` | yes | `SPEC[nlcc]` |
| `--rcore` | yes | `SPEC[rcore]` |
| `--rho0` | yes | `--` |
| `--augfun`, `--which-augfun` | yes | `SPEC[which_augfun]` |
| `--rmatch` | yes | `SPEC[rmatch_augfun]` |
| `--lloc` | yes | `SPEC[lloc]` |
| `--rcloc` | yes | `SPEC[rcloc]` |
| `--projector` | yes | `SPEC[extra_projectors]` |
| `--rcut-scale` | yes | `SPEC[rcut_scale]` |
| `--nc-form` | yes | `SPEC[nc_form]` |
| `--lsd` | no | `SPEC[lsd]` |
| `--gipaw` | no | `SPEC[gipaw]` |
| `--refit` | no | `GTH_REFIT` |
| `--refit-cycles` | yes | `GTH_CYCLES` |
| `--grid` | yes | `SPEC[xmin]` |
| `--beta` | yes | `SPEC[beta]` |
| `--tr2` | yes | `--` |
| `--test` | no | `RUN_LD1_TESTS` |
| `--no-test` | no | `RUN_LD1_TESTS` |
| `--plot` | no | `PLOT_ENABLED` |
| `--no-plot` | no | `PLOT_ENABLED` |
| `--plot-dir` | yes | `PLOT_DIR` |
| `--plot-format` | yes | `PLOT_FORMAT` |
| `--plot-bands` | yes | `PLOT_BANDS_FILE` |
| `--plot-dos` | yes | `PLOT_DOS_FILE` |
| `--plot-rlderiv` | yes | `PLOT_RLDERIV` |
| `--cutoff-scan` | no | `RUN_CUTOFF_SCAN` |
| `--no-cutoff-scan` | no | `RUN_CUTOFF_SCAN` |
| `--cutoffs` | yes | `CUTOFF_SCAN_LIST` |
| `--cutoff-tol` | yes | `CUTOFF_TOL_MRY` |
| `--pw-template` | yes | `PW_TEMPLATE` |
| `--resume` | no | `RESUME` |
| `--no-resume` | no | `RESUME` |
| `--autofix` | no | `AUTOFIX_ENABLED` |
| `--no-autofix` | no | `AUTOFIX_ENABLED` |
| `--attempts` | yes | `AUTOFIX_MAX_ATTEMPTS` |
| `--engine` | yes | `CLI_ENGINE` |
| `--source` | yes | `CLI_SOURCE` |
| `--params` | yes | `PARAMS_DIR` |
| `--mirror` | yes | `MIRROR_URL` |
| `--format`, `--formats` | yes | `CLI_FORMATS` |
| `--attribution` | no | `CLI_ATTRIBUTION` |
| `--show-citation` | yes | `CLI_SHOW_CITATION` |
| `--dry-run` | no | `CLI_DRYRUN` |
| `-q`, `--quiet` | no | `PF_QUIET` |
| `-v`, `--verbose` | no | `PF_VERBOSE` |
| `--no-color` | no | `C_RESET` |
| `-h`, `--help` | no | `--` |
| `--` | no | `--` |

<!-- generated:end -->


---

## Notes on the options that need them

### Element selection

`-e/--elements` accepts symbols, atomic numbers and selectors, comma- or
space-separated. Several `-e` on one line accumulate. See
[Elements and selectors](elements.md) for the full list.

```bash
pseudoforge generate -e Si,Ge -t paw -p psl-high -x pbe
pseudoforge generate -e transition-metals -t paw -p psl-high -x pbe
```

!!! warning "`-e` after `--recipe` replaces, it does not add"
    A saved recipe carries an element list. An explicit `-e` alongside
    `--recipe` **replaces** that list rather than appending to it — the rule
    everywhere else is that an explicit flag overrides the recipe, and
    `--recipe r -e Fe` quietly generating three elements is not that. Without a
    recipe, several `-e` still accumulate as before.

### `--recipe`

Applied in a pre-pass, before any other flag is parsed, so position does not
change meaning: `--recipe r -x pbesol` and `-x pbesol --recipe r` do the same
thing, and in both the explicit flag wins. See [Recipe files](recipes.md).

### `--engine`

Defaults to the engine the profile and family imply. An explicit engine is
checked against what it can do before anything is written:

```text
$ pseudoforge generate -e Si -t us --engine oncvpsp
ERROR ONCVPSP (Hamann) cannot make us pseudopotentials (it does: nc)
```

### `--rel`

`nonrel`, `scalar` (the default) or `full`. Full-relativistic generation
produces j-dependent projectors and is what you want for spin-orbit coupling.
Not every engine implements all three — see the engine pages.

### `--rho0`

Sets `rho0` in the `&inputp` namelist of an `ld1.x` deck. PseudoForge passes
the value through without interpreting it; for what it means, see the `ld1.x`
documentation in the Quantum ESPRESSO distribution.

### `--plot`

Draws log derivatives and radial wavefunctions after the run. With no plotting
backend installed it says so and exits 0 — see [Plot the
diagnostics](../how-to/plot.md).

### `--dry-run`

Assembles and validates the whole specification, prints what would be
generated, and stops before running an engine. The fastest way to check that a
long command means what you think.

---

## Exit codes

| Code | Meaning |
|---|---|
| `0` | everything asked for succeeded, or succeeded with warnings |
| `1` | at least one element failed, or the request was refused |
| `2` | usage error — an unknown command or a malformed option |

A batch returns 1 if any element failed, after attempting all of them. One
element failing never stops the others; see
[failure isolation](../architecture/validation.md#failure-isolation).

---

## Configuration file

`~/.pseudoforgerc` is plain shell, sourced at startup, and is where paths
belong so they do not have to be repeated on every command line.

```bash
pseudoforge config --show          # what is set now
pseudoforge config --set QE_ROOT_DIR=/opt/espresso/7.6
pseudoforge config --edit          # in $EDITOR
```

Everything in it can be overridden by an environment variable or a flag for a
single run. See [Installation](../getting-started/installation.md) for the keys
that matter.
