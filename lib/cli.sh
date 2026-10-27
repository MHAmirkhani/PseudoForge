# shellcheck shell=bash
# ---------------------------------------------------------------------------
# cli.sh -- the non-interactive command line.
#
# Everything the TUI can do is reachable from here, because that is what makes
# the tool usable in a job script:
#
#   pseudoforge generate --elements Fe,Si,O --family paw --xc pbe --rel scalar
#   pseudoforge generate --elements 1-36 --profile psl-low --jobs 16 --cutoff-scan
#   pseudoforge validate pseudos/*.UPF
# ---------------------------------------------------------------------------

cli_usage() {
cat <<HELPEOF
PseudoForge $PSEUDOFORGE_VERSION -- multi-engine pseudopotential generator and validator

USAGE
    PseudoForge [command] [options]

    wizard                  guided flow, straight to the first layer
    tui                     the full menu (guided, quick, browse, settings)
                            -- also what a bare PseudoForge runs
    engines <sub>           list | build <name>|all | show <name> | path <name>
    generate                generate pseudopotentials
    validate <file>...      structural check of existing files (any format)
    convert <file> --to F   convert between formats (--list shows the paths)
    import <dir>            register third-party UPFs into a project and test them
    native <sub>            index | list | size [dir]
    report [project]        rebuild the reports of an existing project
    list <what>             profiles | functionals | elements | recipes | sets
    show <profile>          full description of a library profile
    recipe <element>        print the ld1.x deck that would be generated
    recipe save <name>      save the current settings as a named recipe
    recipe load <name>      show the command a saved recipe is equivalent to
    recipe list             list saved recipes
    recipe export <name>    write a recipe out to share it
    recipe import <file>    take one in
    compare <a> <b>         compare two pseudopotentials side by side
    citation <library>      the citations for a library (--all for every one)
    params <sub>            status | fetch | path | extract (library inputs)
    profile <sub>           list | new | edit | remove (library profiles)
    xc <sub>                list | add | remove (functionals)
    api <method> <path>     call the local API server (api --routes lists them)
    optimise -e EL [opts]   sweep --rcut-scale and pick the softest radii that
                            still pass transferability (ld1 oncvpsp opium ape)
    plot <project>          draw log derivatives and wavefunctions for a run
    doctor                  check the environment and the recipe database
    advise -e EL [opts]     physics reasoning on which pseudopotential to choose
    provenance <id>         show provenance record for a native file
    element <symbol>        list native store files and missing profiles for an element
    coverage [--profile P]  matrix of element x profile availability
    recent [--count N]      show most recently added files to the store
    capabilities            show capability matrix across deployment tiers
    config [--show|--edit|--set K=V]
    version | help

ENGINE AND SOURCE
  --engine NAME               $(eng_list 2>/dev/null | paste -sd'|' - | sed 's/|/ | /g')
                              default: chosen from the profile and family
  --source local|online       generate here, or download a published file
  --params DIR                a library's own generator inputs, for a real
                              reproduction rather than PseudoForge's construction
  --mirror URL                override MIRROR_URL for this run

GENERATION OPTIONS
    -e, --elements LIST     Fe,Si,O | 1-36 | all | block:d | series:lanthanide
                            period:4 | group:16 | transition-metals | !Fe to exclude
    -t, --family NAME       nc | us | paw                    (default: $DEFAULT_PSEUDOTYPE)
    -p, --profile NAME      library profile                  (default: $DEFAULT_PROFILE)
    -x, --xc NAME           functional, e.g. pbe pbesol scan  (default: $DEFAULT_XC)
    -r, --rel MODE          nonrel | scalar | full            (default: $DEFAULT_RELATIVITY)
        --variant TAG       pick a specific PSlibrary variant (e.g. spn, dn, nl)
        --upf 1|2           UPF output format                 (default: v$DEFAULT_UPF_VERSION)
    -o, --output DIR        project directory
    -j, --jobs N            parallel elements                 (default: $MAX_PARALLEL_JOBS)
        --plot              draw log derivatives and wavefunctions after the run
        --recipe NAME       start from a saved recipe; explicit flags override
        --author NAME       author string written into the UPF

PHYSICS OPTIONS
        --config STR        override the atomic configuration, e.g. '[Ar] 3d7 4s1'
        --core-hole SHELL   remove one electron from SHELL (e.g. 1s) for XPS/XAS
        --zed VALUE         fractional nuclear charge (virtual-crystal pseudopotentials)
        --zval VALUE        explicit valence charge.  Rarely needed: with
                            --core-hole, ld1.x already counts the missing
                            core electron as valence charge.
        --nlcc on|off       nonlinear core correction
        --rcore VALUE       NLCC matching radius
        --augfun NAME       AE | PSQ | BESSEL | GAUSS | BG    (US/PAW only)
        --rmatch VALUE      augmentation matching radius
        --lloc L            local channel (-1 = all-electron potential)
        --rcloc VALUE       local channel cut-off radius
        --projector S:E     extra projector, e.g. 3D:0.5 (repeatable)
        --rcut-scale F      scale every cut-off radius by F (ld1, oncvpsp, opium, ape;
                            refused with the reason for the other engines)
        --nc-form FORM      separable (default) or semilocal, NC only
        --lsd               spin-polarised generation
        --gipaw             write GIPAW reconstruction data (NMR/EPR)
        --refit             GTH only: re-run the fit from the library's own
                            starting parameters instead of writing the
                            published coefficients. The result is close to
                            the published one but is not it, and is labelled
                            PSEUDOFORGE.
        --refit-cycles N    fit cycles for --refit (default 200)
        --grid XMIN:DX:RMAX radial grid, e.g. -7.0:0.0125:100.0
        --beta VALUE        SCF mixing factor
        --tr2 VALUE         SCF convergence threshold

VALIDATION OPTIONS
        --test / --no-test          transferability check, using the analysis the
                                    chosen engine provides       (default: on)
        --cutoff-scan               pw.x kinetic-energy cutoff scan (default: off)
        --cutoffs "30 40 50 ..."    the ladder to scan
        --cutoff-tol MRY            convergence target, mRy/atom
        --pw-template FILE          use your own pw.x input for the scan instead of
                                    a generic fcc cell; placeholders {{ELEMENT}}
                                    {{UPF}} {{MASS}} {{ECUTWFC}} {{ECUTRHO}}
                                    {{PSEUDO_DIR}} {{OUTDIR}} {{PREFIX}} {{CELLDM}}

BEHAVIOUR
        --resume / --no-resume      skip elements already finished (default: on)
        --autofix / --no-autofix    retry failures with relaxed parameters (default: on)
        --attempts N                auto-fix attempts per element
        --dry-run                   write the decks, run nothing
    -q, --quiet                 -v, --verbose                 --no-color

EXAMPLES
    pseudoforge generate -e Fe,Ni,Co -t paw -x pbe --cutoff-scan
    pseudoforge generate -e all -p psl-low -t us -j 16 -o ~/pp/pslow-pbe
    pseudoforge generate -e Cu --core-hole 1s -o ~/pp/cu-corehole
    pseudoforge generate -e Pt -t nc -x scan          # warns: generated with PBE
    pseudoforge recipe Fe -t paw -p psl-high          # inspect before committing
    pseudoforge recipe save mypaw -e Si,Fe -t paw    # keep these settings
    pseudoforge generate --recipe mypaw              # and run them again

CREDIT
    PseudoForge is written and maintained by Mohammad H. Amirkhani
    <https://amirkhani.me> and distributed under the GNU GPL v2 or later.

    It generates pseudopotentials with atomic codes it does not own.  Cite the
    library you used, and the generator that produced it:
        pseudoforge citation <library>
        pseudoforge generate ... --attribution

HELPEOF
}

# ---------------------------------------------------------------------------
# cli_help_for -- per-subcommand help for `pseudoforge <sub> --help`.
#
# The global help (cli_usage) carries the full option list.  This is a
# per-command summary, so `pseudoforge <sub> --help` exits 0 and says what
# the subcommand does, rather than printing the global help or erroring out
# with "unknown option: --help".
# ---------------------------------------------------------------------------
cli_help_for() {
    local sub=$1
    case $sub in
        generate|wizard) cli_usage ;;
        version) printf 'usage: pseudoforge version\n\nPrint the version, the copyright and the author.\n' ;;
        help)    cli_usage ;;
        validate) cat <<'EOF'
usage: pseudoforge validate <file>...

Structural check of existing pseudopotential files.  Checks each file
against its own format: UPF (v1 and v2), psp8, PAW-XML, GTH, OpenMX .vps.
Structure and integrity only -- transferability and cutoffs are measured
by `pseudoforge generate`.
EOF
        ;;
        convert) cat <<'EOF'
usage: pseudoforge convert <file> --to <format> [-o DIR]
       pseudoforge convert --list
       pseudoforge convert --why <from> <to>

Convert between pseudopotential formats.  Only paths a real tool performs
are registered and are verified exact against pw.x; anything else is
refused with the reason.  --list shows every path and its cost.
EOF
        ;;
        import) cat <<'EOF'
usage: pseudoforge import <directory-of-UPF-files> [-o project]

Register third-party UPF files into a PseudoForge project and run the
structural checks against them.  The files are not modified; the project
records them so the reports and citation machinery see them.
EOF
        ;;
        engines) cat <<'EOF'
usage: pseudoforge engines list
       pseudoforge engines build <name>|all
       pseudoforge engines show <name>
       pseudoforge engines path <name>

Manage the generator engines PseudoForge drives.  build fetches, configures
and compiles one engine (or all) into PseudoForge's own prefix; path prints
the binary path.
EOF
        ;;
        native) cat <<'EOF'
usage: pseudoforge native index|list|size [dir]

Manage the native store -- the pre-built files the website serves.
  index   rebuild index.tsv from the store
  list    print the entries
  size    per-engine summary
Default directory: $PF_NATIVE_DIR.
EOF
        ;;
        doctor) cat <<'EOF'
usage: pseudoforge doctor [--json|--tui|--check]

Check the environment PseudoForge runs in: engine binaries, the recipe
database, the download mirror, and the store.  --json prints the same
information in machine-readable form; --tui opens an interactive menu;
--check exits 1 if required dependencies are missing.
EOF
        ;;
        list) cat <<'EOF'
usage: pseudoforge list <what>

  profiles     every library profile, with provenance and coverage
  functionals  every exchange-correlation functional
  elements     the periodic table as PseudoForge sees it
  recipes      saved recipes
  sets         PSlibrary sets and their coverage
EOF
        ;;
        show) cat <<'EOF'
usage: pseudoforge show <profile>

Full description of a library profile: what it publishes, what can be
generated for it, its provenance, licence and citation.
EOF
        ;;
        recipe) cat <<'EOF'
usage: pseudoforge recipe <element>  [generate options]   print the deck
       pseudoforge recipe save <name>  [generate options]  save settings
       pseudoforge recipe load <name>                      show the command
       pseudoforge recipe list                             list saved
       pseudoforge recipe export <name>                    write one out
       pseudoforge recipe import <file>                    take one in

Inspect or save the ld1.x deck (and the settings behind it) without
running anything.
EOF
        ;;
        optimise) cat <<'EOF'
usage: pseudoforge optimise -e EL [generate options]

Sweep --rcut-scale and pick the softest cut-off radii that still pass the
engine's own transferability check.  Supported for ld1, oncvpsp, opium
and ape.
EOF
        ;;
        plot) cat <<'EOF'
usage: pseudoforge plot <project>

Draw the log derivatives and pseudo-wavefunctions of a completed run.
Reads the summary of the project rather than re-running anything.
EOF
        ;;
        report) cat <<'EOF'
usage: pseudoforge report [project]

Rebuild the summary.txt / summary.csv / summary.json / summary.html of an
existing project.  Nothing is re-generated.
EOF
        ;;
        config) cat <<'EOF'
usage: pseudoforge config [--show]
       pseudoforge config --template
       pseudoforge config --edit
       pseudoforge config --set KEY=VALUE

Show, print template, edit or set entries in the PseudoForge configuration file
(~/.pseudoforgerc by default, or $PF_RC).
EOF
        ;;
        citation) cat <<'EOF'
usage: pseudoforge citation <library>

Print the citations for a library -- its paper, the generator that made
the file, and PseudoForge itself.  Use --attribution on `generate` for a
per-run citation block.
EOF
        ;;
        advise) cat <<'EOF'
usage: pseudoforge advise -e <element> [options]

Physics-reasoned advice on which pseudopotential to choose.

options:
  -e, --element NAME       required; single element (Fe, Si, U, ...)
      --calculation TYPE   phonons | elastic | eos | band-gap | gw | optics |
                           xas | magnetism | dft-u | md | transport | phonon-2d
                           (default: brief overview across all calculations)
      --code CODE          qe | abinit | vasp | cp2k | siesta | openmx | castep
                           (default: any; affects format preference only)
      --material CLASS     override auto-detected material class:
                           transition-metal | lanthanide | actinide | halogen |
                           noble-gas | alkali-metal | alkaline-earth |
                           main-group | metalloid
      --functional XC      override the calculation's default functional
      --accuracy LEVEL     speed | balanced | stringent (default: balanced)
      --json               emit JSON rather than human text
  -q, --quiet              command only, no banner or reasoning
EOF
        ;;
        provenance) cat <<'EOF'
usage: pseudoforge provenance <id> [--json]

Show full provenance record for a native pseudopotential file: engine,
binary fingerprint, build date, profile, upstream source, generation command,
size, and SHA256.
EOF
        ;;
        element) cat <<'EOF'
usage: pseudoforge element <symbol> [--json]

List all native files in the store for an element grouped by family (NC, PAW,
US) and functional, with sizes and engines.  Also lists missing profiles with
copyable commands to generate them.
EOF
        ;;
        coverage) cat <<'EOF'
usage: pseudoforge coverage [--profile <prof>] [--element <el>] [--json]

Show element x profile availability matrix: what is in store (green),
what is buildable locally (blue), what is import-only (yellow), and what
is absent (white).
EOF
        ;;
        recent) cat <<'EOF'
usage: pseudoforge recent [--count <n>] [--json]

Show the most recently added files in the store, most recent first.
Default count is 10.
EOF
        ;;
        capabilities) cat <<'EOF'
usage: pseudoforge capabilities [--json]

Show honest capability matrix: what can be done with the store alone,
with CLI installed but no engines, and with CLI plus engines.
EOF
        ;;
        cutoff) cat <<'EOF'
usage: pseudoforge cutoff -e <element> [--accuracy efficiency|precision] [--xc PBE|PBEsol] [-o <project-dir>] [--json]

Report recommended kinetic-energy cutoff (ecutwfc and ecutrho) for an element.
Drawn from SSSP verification tables, PseudoDojo parameters, or project scans.
EOF
        ;;
        tui)     cli_usage ;;
        *)       cli_usage ;;
    esac
}

# ---------------------------------------------------------------------------
CLI_ELEMENTS=""
CLI_ELEMENTS_FROM_RECIPE=
CLI_OUTPUT=""
CLI_DRYRUN=0
CLI_ENGINE=
CLI_SOURCE=
CLI_ATTRIBUTION=0
CLI_SHOW_CITATION=

# ---------------------------------------------------------------------------
# cli_recipe_preload -- apply --recipe before any other flag is parsed.
#
# Position must not change meaning.  If the recipe were loaded where it appears
# in the argument list, `--recipe r -x pbe` and `-x pbe --recipe r` would do
# different things, and only one of them would be what anybody meant.  Loading
# first and parsing afterwards makes an explicit flag always win, wherever it
# sits.
# ---------------------------------------------------------------------------
cli_recipe_preload() {
    while [ $# -gt 0 ]; do
        case $1 in
            --recipe) [ -n "${2:-}" ] || die "--recipe needs a name"
                      rcp_load "$2" || exit 1
                      [ -n "$CLI_ELEMENTS" ] && CLI_ELEMENTS_FROM_RECIPE=1
                      info "loaded recipe: $(basename "$RCP_LOADED" .recipe)"
                      return 0 ;;
            *)        shift ;;
        esac
    done
    return 0
}

cli_parse() {
    local grid
    cli_recipe_preload "$@"
    while [ $# -gt 0 ]; do
        case $1 in
            advise|advisory) shift; cmd_advise "$@"; exit 0 ;;
            provenance) shift; cmd_provenance "$@"; exit 0 ;;
            element) shift; cmd_element "$@"; exit 0 ;;
            coverage) shift; cmd_coverage "$@"; exit 0 ;;
            recent) shift; cmd_recent "$@"; exit 0 ;;
            capabilities) shift; cmd_capabilities "$@"; exit 0 ;;
            cutoff) shift; cmd_cutoff "$@"; exit 0 ;;
            -e|--elements)
                            # Several -e on one line accumulate, as they always
                            # have.  But the first one after --recipe replaces
                            # the recipe's list rather than adding to it: the
                            # rule everywhere else is that an explicit flag
                            # overrides the recipe, and "-e Fe" quietly
                            # generating Fe, Co and Ni is not that.
                            if [ -n "${CLI_ELEMENTS_FROM_RECIPE:-}" ]; then
                                CLI_ELEMENTS=""; CLI_ELEMENTS_FROM_RECIPE=
                            fi
                            CLI_ELEMENTS="$CLI_ELEMENTS $2"; shift 2 ;;
            -t|--family|--type) SPEC[family]=$(lower "$2"); shift 2 ;;
            -p|--profile)   SPEC[profile]=$2; shift 2 ;;
            -x|--xc|--functional) SPEC[xc]=$(lower "$2"); shift 2 ;;
            -r|--rel|--relativity) SPEC[rel]=$2; shift 2 ;;
            --recipe)       shift 2 ;;   # handled by cli_recipe_preload
            --variant)      SPEC[variant]=$2; shift 2 ;;
            --upf)          SPEC[upf]=$2; shift 2 ;;
            -o|--output)    CLI_OUTPUT=$2; shift 2 ;;
            -j|--jobs)      MAX_PARALLEL_JOBS=$2; shift 2 ;;
            --author)       SPEC[author]=$2; shift 2 ;;

            --config)       SPEC[config]=$2; shift 2 ;;
            --core-hole)    SPEC[core_hole]=$2; shift 2 ;;
            --zed)          SPEC[zed]=$2; shift 2 ;;
            --zval)         SPEC[zval]=$2; shift 2 ;;
            --nlcc)         SPEC[nlcc]=$(lower "$2"); shift 2 ;;
            --rcore)        SPEC[rcore]=$2; shift 2 ;;
            --rho0)         SPEC[rho0]=$2; shift 2 ;;
            --augfun|--which-augfun) SPEC[which_augfun]=$2; shift 2 ;;
            --rmatch)       SPEC[rmatch_augfun]=$2; shift 2 ;;
            --lloc)         SPEC[lloc]=$2; shift 2 ;;
            --rcloc)        SPEC[rcloc]=$2; shift 2 ;;
            --projector)    SPEC[extra_projectors]="${SPEC[extra_projectors]} $2"; shift 2 ;;
            --rcut-scale)   SPEC[rcut_scale]=$2; shift 2 ;;
            --nc-form)      SPEC[nc_form]=$(lower "$2"); shift 2 ;;
            --lsd)          SPEC[lsd]=1; shift ;;
            --gipaw)        SPEC[gipaw]=1; shift ;;
            --refit)        GTH_REFIT=1; export GTH_REFIT; shift ;;
            --refit-cycles) GTH_CYCLES=$2; export GTH_CYCLES; shift 2 ;;
            --grid)         grid=$2
                            SPEC[xmin]=${grid%%:*}
                            SPEC[dx]=$(printf '%s' "$grid" | cut -d: -f2)
                            SPEC[rmax]=${grid##*:}
                            shift 2 ;;
            --beta)         SPEC[beta]=$2; shift 2 ;;
            --tr2)          SPEC[tr2]=$2; shift 2 ;;

            --test)         RUN_LD1_TESTS=1; shift ;;
            --no-test)      RUN_LD1_TESTS=0; shift ;;
            --plot)         PLOT_ENABLED=1; shift ;;
            --no-plot)      PLOT_ENABLED=0; shift ;;
            --plot-dir)     PLOT_DIR=$2; shift 2 ;;
            --plot-format)  PLOT_FORMAT=$(lower "$2"); shift 2 ;;
            --plot-bands)   PLOT_BANDS_FILE=$(abspath "$2"); PLOT_ENABLED=1; shift 2 ;;
            --plot-dos)     PLOT_DOS_FILE=$(abspath "$2"); PLOT_ENABLED=1; shift 2 ;;
            --plot-rlderiv) PLOT_RLDERIV=$2; shift 2 ;;
            --cutoff-scan)  RUN_CUTOFF_SCAN=1; shift ;;
            --no-cutoff-scan) RUN_CUTOFF_SCAN=0; shift ;;
            --cutoffs)      CUTOFF_SCAN_LIST=$2; shift 2 ;;
            --cutoff-tol)   CUTOFF_TOL_MRY=$2; shift 2 ;;
            --pw-template)  PW_TEMPLATE=$(abspath "$2"); shift 2 ;;

            --resume)       RESUME=1; shift ;;
            --no-resume)    RESUME=0; shift ;;
            --autofix)      AUTOFIX_ENABLED=1; shift ;;
            --no-autofix)   AUTOFIX_ENABLED=0; shift ;;
            --attempts)     AUTOFIX_MAX_ATTEMPTS=$2; shift 2 ;;
                --engine)   CLI_ENGINE=$(lower "$2"); shift 2
                            eng_exists "$CLI_ENGINE" ||                                 die "unknown engine '$CLI_ENGINE' -- try: pseudoforge engines list" ;;
            --source)   CLI_SOURCE=$(lower "$2"); shift 2
                            case $CLI_SOURCE in
                                local|online) ;;
                                *) die "--source takes 'local' or 'online'" ;;
                            esac ;;
            --params)   PARAMS_DIR=$2; shift 2
                            [ -d "$PARAMS_DIR" ] || die "--params: not a directory: $PARAMS_DIR" ;;
            --mirror)   MIRROR_URL=$2; shift 2 ;;
            --format|--formats) CLI_FORMATS=$2; shift 2 ;;
            --attribution)  CLI_ATTRIBUTION=1; shift ;;
            --show-citation) CLI_SHOW_CITATION=${2:-}; shift 2 ;;
            --dry-run)      CLI_DRYRUN=1; shift ;;

            -q|--quiet)     PF_QUIET=1; shift ;;
            -v|--verbose)   PF_VERBOSE=1; shift ;;
            --no-color)     C_RESET=; C_BOLD=; C_DIM=; C_RED=; C_GREEN=; C_YELLOW=; C_BLUE=; C_CYAN=; shift ;;
            -h|--help)      cli_usage; exit 0 ;;
            --)             shift; break ;;
            -*)             die "unknown option: $1  (pseudoforge help)" ;;
            *)              CLI_ELEMENTS="$CLI_ELEMENTS $1"; shift ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# Validate the assembled spec before touching the disk.  Failing here with a
# clear message beats failing 40 elements in with a Fortran traceback.
# ---------------------------------------------------------------------------
cli_check_spec() {
    local id
    case ${SPEC[family]} in nc|us|paw) ;; *) die "unknown family '${SPEC[family]}' (nc | us | paw)" ;; esac

    prof_exists "${SPEC[profile]}" || die "unknown profile '${SPEC[profile]}' -- try: pseudoforge list profiles"
    prof_supports_family "${SPEC[profile]}" "${SPEC[family]}" || \
        die "profile '${SPEC[profile]}' has no ${SPEC[family]} recipes (it covers: ${PROF_FAMILIES[${SPEC[profile]}]})"

    id=$(xc_canon "${SPEC[xc]}") || die "unknown functional '${SPEC[xc]}' -- try: pseudoforge list functionals"
    SPEC[xc]=$id
    rel_canon "${SPEC[rel]}" >/dev/null || die "unknown relativity '${SPEC[rel]}' (nonrel | scalar | full)"
    SPEC[rel]=$(rel_canon "${SPEC[rel]}")
    case ${SPEC[upf]} in
        2) ;;
        1) die "UPF v1 is not supported by the Quantum ESPRESSO in this build.
  QE 7.x's ld1.x no longer recognises the upf_v1_format namelist key, and
  no other engine here writes UPF v1.  Use --upf 2 (the default), or run
  an older QE (<= 6.x) if you need v1 for a legacy reader." ;;
        *) die "--upf must be 1 or 2" ;;
    esac

    # The functional and relativity the library's own inputs can produce. The
    # wizard always filtered by these (prof_compatible); the command line did
    # not, and so `-p gbrv -x pz` ran GBRV's PBE decks and wrote the result
    # as "Ag.pz-...". The first full build of the native store did that 1,493
    # times across six profiles. Refused here, with the reason the wizard gives.
    if ! prof_supports_xc "${SPEC[profile]}" "${SPEC[xc]}" \
       || ! prof_supports_rel "${SPEC[profile]}" "${SPEC[rel]}"; then
        die "profile '${SPEC[profile]}' has $(prof_incompatible_reason "${SPEC[profile]}" "${SPEC[family]}" "${SPEC[xc]}" "${SPEC[rel]}")
  Its inputs produce functional(s): ${PROF_XC[${SPEC[profile]}]:-any}; relativity: ${PROF_REL[${SPEC[profile]}]:-any}.
  For another combination, use -p pseudoforge-auto (PseudoForge's own construction)."
    fi

    if [ -n "${SPEC[which_augfun]}" ]; then
        case $(upper "${SPEC[which_augfun]}") in
            AE|PSQ|BESSEL|GAUSS|BG) ;;
            *) die "--augfun must be one of AE PSQ BESSEL GAUSS BG" ;;
        esac
        [ "${SPEC[family]}" = nc ] && warn "--augfun has no effect for norm-conserving pseudopotentials"
    fi
    [ "${SPEC[family]}" = nc ] && [ "${SPEC[profile]}" = psl-low ] && \
        die "profile psl-low has no norm-conserving recipes; use psl-high (family nc) or another profile"

    # Which engine will actually run?
    # A --engine flag wins; otherwise keep what a loaded recipe asked for;
    # otherwise derive it.  Assigning the flag unconditionally would have
    # thrown away the recipe's engine without saying so.
    SPEC[engine]=${CLI_ENGINE:-${SPEC[engine]:-}}
    if [ -z "${SPEC[engine]}" ]; then
        if [ "${DEFAULT_ENGINE:-auto}" != auto ]; then
            SPEC[engine]=$DEFAULT_ENGINE
        else
            SPEC[engine]=$(eng_for_profile "${SPEC[profile]}" "${SPEC[family]}")
        fi
    fi
    eng_supports_family "${SPEC[engine]}" "${SPEC[family]}" ||         die "${ENG_LABEL[${SPEC[engine]}]} cannot make ${SPEC[family]} pseudopotentials (it does: ${ENG_FAMILIES[${SPEC[engine]}]})"

    # AtomPAW is the one engine with a real meta-GGA path, and that path does
    # not implement the relativistic solver: it gets as far as the first SCF
    # cycle and stops with "for relativistic solver -- error stop", which
    # reaches the user as "no convergence in boundsr" and explains nothing.
    #
    # Refused rather than quietly switched.  Dropping to a non-relativistic
    # solver changes the physics of the result, and choosing that on someone's
    # behalf is the kind of silent downgrade this tool exists not to do.
    if [ "${SPEC[engine]}" = atompaw ]        && [ "${XC_FAMILY[${SPEC[xc]}]:-}" = metaGGA ]        && [ "$(rel_canon "${SPEC[rel]}")" != nonrel ]; then
        die "AtomPAW cannot generate meta-GGA with a relativistic solver.
  Its ${XC_LABEL[${SPEC[xc]}]:-meta-GGA} path is non-relativistic only.
  Re-run with -r nonrel, or choose a GGA functional to keep ${SPEC[rel]} relativity."
    fi

    # The wizard sets SPEC[source] before calling us; an explicit --source still
    # wins, but do not fall back to the default and quietly undo the user's
    # choice of "download" -- that turned every online run into a local one.
    SPEC[source]=${CLI_SOURCE:-${SPEC[source]:-${DEFAULT_SOURCE:-local}}}

    # Output formats are validated against the engine that will actually run,
    # so a request the engine cannot honour is refused here rather than
    # silently producing a UPF under a different name.
    # Output formats, in order of authority:
    #
    #   1. --format on the command line -- an explicit request.
    #   2. what the profile declares its engine should emit, IF the engine
    #      can honour it.  opium declares its ten formats here; ld1 and
    #      oncvpsp declare upf xml; that is where the multiple-format
    #      default comes from.
    #   3. SPEC[formats] as the TUI, a recipe, or a direct assignment set
    #      it -- validated against the engine.  Some profiles declare a
    #      format their engine cannot write (pseudoforge-auto says "upf
    #      xml" but APE writes only upf), and the format picker sets the
    #      engine's own answer.  Falling through to it keeps the TUI's
    #      choice.
    #   4. the global default.
    #
    # The old order put the profile in front of SPEC[formats] without the
    # "IF the engine can honour it" guard, so a TUI run that had picked
    # upf for APE had SPEC[formats]=upf overwritten by the profile's
    # "upf,xml" and cli_check_spec refused with "APE cannot write xml".
    if [ -n "${CLI_FORMATS:-}" ]; then
        SPEC[formats]=$(fmt_validate "${SPEC[engine]}" "$CLI_FORMATS") || exit 1
    elif [ -n "${PROF_FORMATS[${SPEC[profile]}]:-}" ] \
         && _v=$(fmt_validate "${SPEC[engine]}" \
                       "${PROF_FORMATS[${SPEC[profile]}]// /,}" 2>/dev/null); then
        SPEC[formats]=$_v
    elif [ -n "${SPEC[formats]:-}" ] \
         && _v=$(fmt_validate "${SPEC[engine]}" "${SPEC[formats]}" 2>/dev/null); then
        SPEC[formats]=$_v
    else
        SPEC[formats]=${DEFAULT_FORMATS:-upf}
    fi

    # --rcut-scale is refused here, before any engine runs, for engines where
    # it is not implemented -- it used to be accepted by all of them, applied
    # by one, and still stamped "-rc<f>" into the file name of the rest.
    if [ -n "${SPEC[rcut_scale]:-}" ]; then
        awk -v f="${SPEC[rcut_scale]}" 'BEGIN { exit !(f + 0 > 0) }' \
            || die "--rcut-scale must be a positive number, not '${SPEC[rcut_scale]}'"
        if ! ib_rc_scalable "${SPEC[engine]:-ld1}"; then
            error "--rcut-scale is not available with ${ENG_LABEL[${SPEC[engine]}]:-${SPEC[engine]}}:"
            error "  $(ib_rc_refusal "${SPEC[engine]}")"
            error "  It works with: ld1, oncvpsp, opium, ape."
            exit 1
        fi
    fi

    # --projector is refused here, before any engine runs, for engines whose
    # deck builder does not consume SPEC[extra_projectors].  Only ld1's deck
    # path calls recipe_apply, which is where cards_add_projector runs; every
    # other engine builds its own deck format (oncvpsp's plain-text `.dat`,
    # atompaw's line-oriented input, gth's tables) and would be handed a flag
    # it silently ignores.  That is the same class of bug as --rcut-scale
    # was -- accepted by everyone, applied by one, and stamped "-xp" into the
    # file name of the rest.
    if [ -n "${SPEC[extra_projectors]// /}" ]; then
        case ${SPEC[engine]:-ld1} in
            ld1) ;;
            *) die "--projector is only available with ld1.x in this build.
  The flag adds a second reference energy to a channel in the ld1.x deck.
  ${ENG_LABEL[${SPEC[engine]}]:-${SPEC[engine]}} builds its own deck format and would
  ignore the flag while still stamping '-xp' into the file name -- which is
  exactly the sort of silent mislabelling this tool refuses to do.
  Use --engine ld1, or edit the deck for ${ENG_LABEL[${SPEC[engine]}]:-${SPEC[engine]}} directly." ;;
        esac
    fi

    # ---- can this profile actually be produced here? -----------------------
    #
    # Two separate questions, and conflating them is what makes other tools
    # untrustworthy:
    #
    #   is the *engine* available?      -> a tooling problem, fixable
    #   are the *parameters* available? -> a provenance problem, not fixable
    #                                      by running anything
    #
    # SG15 is ONCVPSP output, and PseudoForge can run ONCVPSP.  That does not make
    # PseudoForge able to produce SG15: the cut-off radii, q-cutoffs and projector
    # counts are the library.  So when the parameters are missing we still run,
    # but the result is labelled as PseudoForge's own and never as theirs.
    if [ "${SPEC[source]}" != online ]; then
        local _eng=${SPEC[engine]}
        if ! prof_can_generate "${SPEC[profile]}" "${SPEC[family]}"; then
            if ! eng_available "$_eng"; then
                error "'${SPEC[profile]}' (${PROF_LABEL[${SPEC[profile]}]}) needs ${ENG_LABEL[$_eng]}, which is not installed."
                error "    pseudoforge engines build $_eng"
                error "Or take the published files:"
                error "    pseudoforge generate -e ... --source online -p ${SPEC[profile]}"
                exit 1
            fi
            error "'${SPEC[profile]}' (${PROF_LABEL[${SPEC[profile]}]}) cannot be reproduced here."
            error "${PROF_NOTES[${SPEC[profile]}]}"
            error "    pseudoforge import <dir> --profile ${SPEC[profile]}"
            exit 1
        fi

        # Fetch the library's own inputs if we do not have them yet.  With them
        # the run is a reproduction; without them it would be PseudoForge's own
        # construction wearing somebody else's name, which we refuse to do
        # silently.
        if [ -z "${PARAMS_DIR:-}" ] && ! prof_has_params "${SPEC[profile]}"; then
            case $(params_kind "${SPEC[profile]}") in
                tarball|github)
                    info "${PROF_LABEL[${SPEC[profile]}]}: fetching the published generation inputs"
                    PARAMS_ELEMENTS="$(el_expand $CLI_ELEMENTS | tr '
' ' ')"                         params_fetch "${SPEC[profile]}" ||                         warn "could not fetch them; the run will use PseudoForge's own parameters and be labelled as such"
                    ;;
            esac
        fi
    fi

    if [ -n "${CLI_SHOW_CITATION:-}" ]; then
        cmd_citation "$CLI_SHOW_CITATION"
        exit 0
    fi
    if [ "${CLI_ATTRIBUTION:-0}" = 1 ]; then
        cli_print_attribution
        exit 0
    fi

    recipe_apply_auto_suffix

    if [ "${XC_STATUS[${SPEC[xc]}]}" = proxy ]; then
        warn "$(xc_explain "${SPEC[xc]}")"
    fi
    if [ "${SPEC[rel]}" = full ] && [ "${SPEC[family]}" = paw ] && [ "${SPEC[profile]}" = psl-tot ]; then
        warn "psl-tot full-relativistic data sets are the ones upstream flags as problematic"
    fi
    return 0
}

# ---------------------------------------------------------------------------
cmd_generate() {
    case "${1:-}" in -h|--help) cli_help_for generate; return 0 ;; esac
    local -a elements
    local el

    [ -n "$CLI_ELEMENTS" ] || die "no elements given: use -e/--elements (pseudoforge help)"
    cli_check_spec

    mapfile -t elements < <(el_expand $CLI_ELEMENTS)
    [ ${#elements[@]} -gt 0 ] || die "element selection '$CLI_ELEMENTS' matched nothing"

    local dir=${CLI_OUTPUT:-$OUTPUT_BASE_DIR/$(project_default_name)}
    project_init "$dir"
    project_write_manifest "${elements[*]}"

    banner "PseudoForge $PSEUDOFORGE_VERSION"
    info "profile    ${PROF_LABEL[${SPEC[profile]}]}  [$(prof_badge "${SPEC[profile]}")]"
    info "family     $(upper "${SPEC[family]}")   functional $(xc_qe_string "${SPEC[xc]}")   $(rel_label "${SPEC[rel]}")"
    info "elements   ${#elements[@]}: ${elements[*]}"
    info "project    $PROJECT_DIR"

    if [ "$CLI_DRYRUN" = 1 ]; then
        banner "Dry run -- writing decks only"
        local _deck _out _prov _src
        for el in "${elements[@]}"; do
            # go through the same builder a real run would, so a dry run tells
            # you about the engine and the parameter source rather than only
            # about ld1
            if IFS=$'\x1f' read -r _deck _out _prov _src \
                   < <(ib_build "${SPEC[engine]}" "$el" "$PROJECT_DIR/inputs") \
               && [ -n "${_deck:-}" ]; then
                ok "$el  ->  ${_deck##*/}   [${_prov:-?}${_src:+: ${_src##*/}}]"
            else
                warn "$el  no input available for ${SPEC[profile]}/${SPEC[family]} with ${SPEC[engine]}"
            fi
        done
        info "decks written to $PROJECT_DIR/inputs"
        return 0
    fi

    deps_resolve_qe
    if [ "${SPEC[source]:-local}" != online ] && [ "${SPEC[engine]:-ld1}" = ld1 ]; then
        if ! deps_have_ld1; then
            if ! pf_ask_install_ld1; then
                die "ld1.x is required and not installed.
  Re-run with PF_AUTO_INSTALL_LD1=yes to allow PseudoForge to install
  it, or install Quantum ESPRESSO and set LD1_BIN."
            fi
        fi
    fi

    banner "Generating"
    if [ "${SPEC[source]:-local}" = online ]; then
        run_online_batch "${elements[@]}"
    else
        run_batch "${elements[@]}"
    fi
    # Before any test: a file must say it is what it is labelled.
    label_verify_batch "${elements[@]}"
    validate_batch "${elements[@]}"

    # attribution travels with the files, not with the project directory: these
    # end up in the same folder people copy into their pseudo_dir
    md_write_attribution "$PROJECT_DIR/pseudos" "${SPEC[profile]}" "${SPEC[engine]:-}"         && info "wrote CITATION.txt and LICENSE.txt to $PROJECT_DIR/pseudos"

    report_all

    # Plots last, and never fatal: a run that produced correct
    # pseudopotentials has not failed because the machine has no gnuplot.
    [ "${PLOT_ENABLED:-0}" = 1 ] && plot_all "$PROJECT_DIR"

    local o w f s n
    read -r o w f s n <<<"$(report_counts)"
    [ "$f" -gt 0 ] && return 1
    return 0
}

# ---------------------------------------------------------------------------
# cmd_plot -- draw the plots for a project that already exists.
#
# Separate from generate so a finished run can be plotted later, on a machine
# that does have a renderer, without regenerating anything.
# ---------------------------------------------------------------------------
cmd_plot() {
    case "${1:-}" in -h|--help) cli_help_for plot; return 0 ;; esac
    local dir=""
    while [ $# -gt 0 ]; do
        case $1 in
            --plot-dir)     PLOT_DIR=$2; shift 2 ;;
            --plot-format)  PLOT_FORMAT=$(lower "$2"); shift 2 ;;
            --plot-bands)   PLOT_BANDS_FILE=$(abspath "$2"); shift 2 ;;
            --plot-dos)     PLOT_DOS_FILE=$(abspath "$2"); shift 2 ;;
            --plot-rlderiv) PLOT_RLDERIV=$2; shift 2 ;;
            -h|--help)      printf 'usage: pseudoforge plot <project-dir> [--plot-dir D] [--plot-format png|svg]
'; return 0 ;;
            -*)             die "unknown option: $1" ;;
            *)              dir=$1; shift ;;
        esac
    done
    [ -n "$dir" ] || die "usage: pseudoforge plot <project-dir>"
    [ -d "$dir" ] || die "no such project: $dir"
    [ -f "$dir/state.tsv" ] || die "$dir is not a PseudoForge project (no state.tsv)"

    PROJECT_DIR=$(abspath "$dir")
    PROJECT_STATE=$PROJECT_DIR/state.tsv
    plot_all "$PROJECT_DIR"
}

# ---------------------------------------------------------------------------
cmd_validate() {
    case "${1:-}" in -h|--help) cli_help_for validate; return 0 ;; esac

    # Strip global behaviour flags before treating the rest as filenames.
    # -q / --quiet / -v / --verbose / --no-color are documented in the
    # global help under BEHAVIOUR, so every subcommand has to accept them.
    local -a args=()
    local a
    for a in "$@"; do
        case $a in
            -q|--quiet|-v|--verbose|--no-color) ;;
            *) args+=("$a") ;;
        esac
    done
    set -- "${args[@]}"

    local f rc=0 problems
    [ $# -gt 0 ] || die "usage: pseudoforge validate <file.UPF>..."
    # A flag used to be treated as a file name: `validate --help` handed
    # "--help" to basename, which printed its own help, and then reported
    # that the file did not exist.
    case $1 in
        -*) die "unknown option: $1  (pseudoforge validate --help)" ;;
    esac
    banner "Validation"
    local v summ notes
    for f in "$@"; do
        # upf_validate_any dispatches by format; this used to call the UPF
        # checker on everything, so a psp8 or .vps file was reported as
        # "no <PP_HEADER> found -- not a UPF file".
        problems=$(upf_validate_any "$f"); v=$?
        summ=""
        case $(lower "${f##*.}") in upf) summ=$(upf_summary "$f") ;; esac
        # NOTE lines describe a file that passed; only other lines are
        # warnings.
        notes=$(printf '%s\n' "$problems" | grep '^NOTE:' | sed 's/^NOTE: *//' | head -1)
        problems=$(printf '%s\n' "$problems" | grep -v '^NOTE:' | sed '/^$/d')
        if [ "$v" -eq 0 ] && [ -z "$problems" ]; then
            ok "$(basename "$f")  ${summ:-$notes}"
        elif [ "$v" -eq 0 ]; then
            warn "$(basename "$f")  ${summ:-$notes}"
            printf '%s\n' "$problems" | sed 's/^/      /'
        else
            error "$(basename "$f")"
            printf '%s\n' "$problems" | sed 's/^/      /'
            rc=1
        fi
    done
    return $rc
}

# ---------------------------------------------------------------------------
cmd_recipe() {
    case "${1:-}" in -h|--help) cli_help_for recipe; return 0 ;; esac
    local el=${1:-}
    case $el in
        ''|-h|--help)
            printf 'usage: pseudoforge recipe <element> [generate options]   print the ld1.x deck\n'
            printf '       pseudoforge recipe save|load|show|list|delete|export|import|path ...\n'
            [ -n "$el" ]; return ;;
    esac
    # The message used "$1", which after the caller's shift is unset -- so
    # under `set -u` a mistyped element crashed with "unbound variable"
    # instead of saying which element it did not know.
    el=$(el_canon "$el") || die "unknown element: $el"
    cli_check_spec
    local tmp; tmp=$(mktemp -d)
    local deck upf set tag
    if recipe_build "$el" "$tmp" >/dev/null; then
        deck=$RB_DECK upf=$RB_UPF set=$RB_SET tag=$RB_TAG
        printf '%s# %s: %s recipe from %s (variant %s)%s\n' \
               "$C_DIM" "$el" "$(upper "${SPEC[family]}")" "$set" "$tag" "$C_RESET" >&2
        printf '%s# -> %s%s\n\n' "$C_DIM" "$upf" "$C_RESET" >&2
        cat "$deck"
    else
        if [ -n "${RB_ERROR:-}" ]; then
            error "$el: $RB_ERROR"
        else
            error "$el: no recipe in profile ${SPEC[profile]} for family ${SPEC[family]}"
        fi
        local alt
        for alt in $(prof_list); do
            prof_is_generatable "$alt" || continue
            prof_supports_family "$alt" "${SPEC[family]}" || continue
            if psl_recipes "$(prof_psl_set "$alt" "${SPEC[family]}")" "$el" | grep -q .; then
                info "  available in profile: $alt"
            fi
        done
        rm -rf "$tmp"; return 1
    fi
    rm -rf "$tmp"
}

# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# cmd_doctor -- what is present, what is missing, and what to run about it.
#
# Nine engines with different build systems and three shared dependencies is
# more than anyone should have to reconstruct from error messages.  This says
# it in one screen, and every "missing" line carries the command that fixes
# it.
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# cmd_doctor -- the CLI front end for the checks in lib/doctor.sh.
#
# The checks and the rendering are separate: doctor_checks produces records,
# and this picks a renderer.  That is what lets the TUI show the same findings
# in a panel and the web API return them as JSON without running anything
# twice or scraping printed text.
# ---------------------------------------------------------------------------
cmd_doctor() {
    case "${1:-}" in -h|--help) cli_help_for doctor; return 0 ;; esac
    local fmt=cli recs check=0 PF_PROMPT_QE_RECORD=0
    [ "${PF_DOCTOR_STRICT:-0}" = 1 ] && check=1
    while [ $# -gt 0 ]; do
        case $1 in
            --json)  fmt=json ;;
            --tui)   fmt=tui ;;
            --check) check=1 ;;
            -*)      die "unknown option: $1" ;;
        esac
        shift
    done

    recs=$(doctor_checks)

    case $fmt in
        json) doctor_render_json "$recs" ;;
        tui)  doctor_render_tui  "$recs" ;;
        *)    doctor_render_cli  "$recs"
              # deps_report covers the download mirror and directories; it was
              # part of this command before the split and stays part of it.
              deps_report ;;
    esac

    if [ "$check" -eq 1 ]; then
        local missing
        missing=$(doctor_missing_required "$recs")
        if [ -n "$missing" ]; then
            error "missing required dependencies:$missing"
            return 1
        fi
    fi
    return 0
}


# ---------------------------------------------------------------------------
# cmd_convert -- pseudoforge convert <file> --to <format>
# ---------------------------------------------------------------------------
cmd_convert() {
    case "${1:-}" in -h|--help) cli_help_for convert; return 0 ;; esac
    pf_convert_load
    local src="" to="" out=""
    while [ $# -gt 0 ]; do
        case $1 in
            --list)   cvt_report; return 0 ;;
            --why)    shift; cvt_why "${1:-}" "${2:-}"; return $? ;;
            --to)     shift; to=${1:-} ;;
            -o|--output) shift; out=${1:-} ;;
            # Global behaviour flags, accepted everywhere but not acted on here.
            -q|--quiet|-v|--verbose|--no-color) ;;
            -*)       die "unknown option: $1" ;;
            *)        src=$1 ;;
        esac
        shift
    done
    [ -n "$src" ] || die "convert what?  pseudoforge convert <file> --to <format>"
    [ -n "$to" ]  || die "convert to what?  --to upf | xml   (--list shows the paths)"
    local made
    made=$(cvt_convert "$src" "$to" "${out:-}") || return 1
    ok "$(basename "$src") -> $made"
    info "record: $made.provenance"
}

cmd_list() {
    case "${1:-}" in -h|--help) cli_help_for list; return 0 ;; esac
    case ${1:-profiles} in
    profiles)
        banner "Library profiles"
        local id fam
        printf '%s %-16s %-12s %-14s %s
' " " ID PROVENANCE FAMILIES LABEL
        printf '  %s\n' "$(printf '%.0s-' $(seq 1 86))"
        for id in $(prof_list_sorted ""); do
            printf '%s %-16s %-12s %-14s %s
' "$(prof_star "$id")" "$id" "$(prof_badge "$id")" \
                   "${PROF_FAMILIES[$id]:-}" "${PROF_LABEL[$id]}"
        done
        printf '\n  Coverage of the generatable profiles (elements with a recipe):\n'
        printf '  %-16s %6s %6s %6s\n' PROFILE PAW US NC
        for id in $(prof_list_sorted ""); do
            prof_can_generate "$id" paw || prof_can_generate "$id" us || prof_can_generate "$id" nc || continue
            [ "$id" = pseudoforge-auto ] && continue
            printf '  %-16s %6s %6s %6s\n' "$id" \
                   "$(prof_coverage_count "$id" paw)" "$(prof_coverage_count "$id" us)" "$(prof_coverage_count "$id" nc)"
        done
    printf '\n  %-13s %s\n'   "generated"    "recipes ship with PseudoForge, byte-identical to upstream"
    printf '  %-13s %s\n'     "generatable"  "the authors publish their inputs and we already hold them"
    printf '  %-13s %s\n'     "fetch inputs" "the same, but downloaded on first use"
    printf '  %-13s %s\n\n'   "import-only"  "genuinely not reproducible; the profile says why"
    printf '
  %s

' "* marks a library that cannot be generated here; those are listed last."
        ;;
    functionals|xc)
        banner "Exchange-correlation functionals"
        local fam id
        for fam in "${XC_FAMILIES[@]}"; do
            printf '\n  %s%s%s\n' "$C_BOLD" "$fam" "$C_RESET"
            for id in $(xc_list_family "$fam"); do
                if xc_is_native "$id"; then
                    printf '    %s%-14s%s %-40s dft=%s\n' "$C_GREEN" "$id" "$C_RESET" "${XC_LABEL[$id]}" "${XC_QE[$id]}"
                else
                    printf '    %s%-14s%s %-40s generated with %s\n' "$C_YELLOW" "$id" "$C_RESET" \
                           "${XC_LABEL[$id]}" "$(xc_qe_string "$id")"
                fi
            done
        done
        printf '\n  %sGreen%s: ld1.x generates directly.  %sYellow%s: ld1.x has no solver for that\n' \
               "$C_GREEN" "$C_RESET" "$C_YELLOW" "$C_RESET"
        printf '  family, so pseudoforge generates with the accepted semilocal parent and says so.\n'
        ;;
    elements)
        banner "Periodic table"
        pf_elements_load
        local s
        for s in "${EL_ORDER[@]}"; do
            printf '  %3s %-3s %-14s %-6s %-16s rcov=%s\n' \
                   "${EL_Z[$s]}" "$s" "${EL_NAME[$s]}" "${EL_BLOCK[$s]}-block" "${EL_SERIES[$s]}" "${EL_RCOV[$s]}"
        done
        ;;
        formats)   fmt_list ;;
    sets)
        banner "PSlibrary recipe sets"
        local f sid
        for f in "$PF_DATA"/psl/*.index; do
            sid=$(basename "$f" .index)
            printf '  %-10s %4s recipes  %3s elements  %s\n' "$sid" \
                   "$(wc -l < "$f" | tr -d ' ')" \
                   "$(psl_set_elements "$sid" | wc -l | tr -d ' ')" \
                   "$(psl_set_elements "$sid" | tr '\n' ' ' | cut -c1-60)..."
        done
        ;;
    recipes)
        shift
        local el=${1:-}
        [ -n "$el" ] || die "usage: pseudoforge list recipes <element>"
        el=$(el_canon "$el") || die "unknown element: $1"
        banner "Recipes for $el ($(el_describe "$el"))"
        local sid tag key cond
        for f in "$PF_DATA"/psl/*.index; do
            sid=$(basename "$f" .index)
            while IFS=$'\t' read -r tag key cond; do
                printf '  %-10s %-14s %-42s %s\n' "$sid" "$tag" "${key//\{\{FCT\}\}/<fct>}" \
                       "$([ "$cond" = any ] && echo "" || echo "($cond only)")"
            done < <(psl_recipes "$sid" "$el")
        done
        ;;
    sssp)
        # SSSP is a table of choices, not a library, so it gets its own view:
        # which library won each element and at what cut-off.
        sssp_report "${SPEC[xc]:-pbe}" ;;
    *) die "list what?  profiles | functionals | formats | elements | sets | sssp | recipes <element>" ;;
    esac
}

cmd_show() {
    case "${1:-}" in -h|--help) cli_help_for show; return 0 ;; esac
    local id=${1:-}
    [ -n "$id" ] || die "usage: pseudoforge show <profile>"
    prof_exists "$id" || die "unknown profile: $id"
    printf '\n'; prof_describe "$id"; printf '\n'
    if prof_is_generatable "$id" && [ "$id" != pseudoforge-auto ]; then
        local fam set
        for fam in paw us nc; do
            set=$(prof_psl_set "$id" "$fam"); [ -n "$set" ] || continue
            printf '  %s: %s elements\n' "$(upper "$fam")" "$(psl_set_elements "$set" | wc -l | tr -d ' ')"
            psl_set_elements "$set" | tr '\n' ' ' | fold -s -w 72 | sed 's/^/      /'
            printf '\n'
        done
    fi
}

# ---------------------------------------------------------------------------
cmd_import() {
    case "${1:-}" in -h|--help) cli_help_for import; return 0 ;; esac
    local src=${1:-}
    [ -n "$src" ] && [ -d "$src" ] || die "usage: pseudoforge import <directory-of-UPF-files> [-o project]"
    shift
    cli_parse "$@"

    local dir=${CLI_OUTPUT:-$OUTPUT_BASE_DIR/import-$(basename "$src")-$(date +%Y%m%d-%H%M%S)}
    project_init "$dir"

    banner "Importing pseudopotentials from $src"
    local f el upf n=0 problems status
    for f in "$src"/*.UPF "$src"/*.upf; do
        [ -e "$f" ] || continue
        upf=$(basename "$f")
        el=$(upf_get "$f" element); el=$(trim "${el:-}")
        [ -n "$el" ] || el=${upf%%.*}
        el=$(el_canon "$el") || { warn "$upf: cannot identify the element; skipped"; continue; }
        cp -f "$f" "$PROJECT_DIR/pseudos/$upf"
        problems=$(upf_validate "$PROJECT_DIR/pseudos/$upf")
        if [ $? -eq 0 ] && [ -z "$problems" ]; then status=ok; else status=ok-warn; fi
        printf '%s' "$problems" | grep -q '^ERROR' && status=fail
        state_record "$el" "${SPEC[family]}" "${SPEC[profile]}" "${SPEC[xc]}" "${SPEC[rel]}" \
                     imported "$upf" "$status" 0 0 "$(printf '%s' "$problems" | tr '\n' '; ' | cut -c1-200)"
        n=$((n + 1))
        case $status in
            ok)   ok   "$upf  $(upf_summary "$PROJECT_DIR/pseudos/$upf")" ;;
            fail) error "$upf  $(printf '%s' "$problems" | head -1)" ;;
            *)    warn "$upf  $(printf '%s' "$problems" | head -1)" ;;
        esac
    done
    [ "$n" -gt 0 ] || die "no UPF files found in $src"
    state_merge
    info "imported $n file(s) into $PROJECT_DIR/pseudos"

    if [ "${RUN_CUTOFF_SCAN:-0}" = 1 ]; then
        mapfile -t els < <(state_list)
        validate_batch "${els[@]}"
    fi
    report_all
}

# ---------------------------------------------------------------------------
cmd_report() {
    case "${1:-}" in -h|--help) cli_help_for report; return 0 ;; esac
    local dir=${1:-}
    [ -n "$dir" ] || die "usage: pseudoforge report <project-directory>"
    [ -f "$dir/state.tsv" ] || die "not a PseudoForge project (no state.tsv): $dir"
    project_init "$dir"
    # restore the settings this project was made with
    if [ -f "$dir/manifest" ]; then
        local k v
        while IFS='=' read -r k v; do
            case $k in \#*|created|host|ld1_bin|ld1_version|pw_bin|elements|xc_*|profile_provenance) continue ;; esac
            [ -n "$k" ] && SPEC[$k]=$v
        done < "$dir/manifest"
    fi
    report_all
}

cmd_config() {
    case "${1:-}" in -h|--help) cli_help_for config; return 0 ;; esac
    case ${1:---show} in
        --show|show) banner "Configuration ($PF_RC)"; pf_config_show ;;
        --template|template) pf_config_template ;;
        --edit|edit) "${EDITOR:-vi}" "$PF_RC" ;;
        --path|path) printf '%s\n' "$PF_RC" ;;
        --set|set)   shift
                     local kv
                     for kv in "$@"; do pf_config_set "${kv%%=*}" "${kv#*=}"; ok "${kv%%=*} = ${kv#*=}"; done ;;
        *) die "usage: pseudoforge config [--show|--template|--edit|--path|--set KEY=VALUE ...]" ;;
    esac
}

# ---------------------------------------------------------------------------
# pseudoforge engines [list|build|show] -- manage the generator engines.
# ---------------------------------------------------------------------------
cmd_engines() {
    case "${1:-}" in -h|--help) cli_help_for engines; return 0 ;; esac
    local sub=${1:-list}; [ $# -gt 0 ] && shift
    case "${1:-}" in
        -h|--help)
            case $sub in
                list)  printf 'usage: pseudoforge engines list\n' ;;
                build)
                    pf_engines_load
                    printf 'usage: pseudoforge engines build <name>|all [--yes]\n\n'
                    printf 'Available engines: %s\n' "${ENG_ORDER[*]}"
                    printf '  all builds eight engines (excludes ld1, which is built on demand)\n'
                    ;;
                show)  printf 'usage: pseudoforge engines show <name>\n' ;;
                path)  printf 'usage: pseudoforge engines path <name>\n' ;;
                *)     printf 'usage: pseudoforge engines list|build|show|path\n' ;;
            esac
            return 0 ;;
    esac
    pf_engines_load
    case $sub in
        list|ls|"")
            banner "Generator engines"
            local eng state detail mark
            for eng in "${ENG_ORDER[@]}"; do
                IFS=$'\t' read -r state detail < <(eng_status "$eng")
                case $state in
                    installed) mark="$C_GREEN installed $C_RESET" ;;
                    buildable) mark="$C_YELLOW buildable $C_RESET" ;;
                    *)         mark="$C_RED  missing  $C_RESET" ;;
                esac
                printf '  %b %-26s %-12s %s\n' "$mark" "${ENG_LABEL[$eng]}" \
                       "${ENG_FAMILIES[$eng]}" "$detail"
            done
            printf '\n  buildable -> pseudoforge engines build <name>\n'
            printf '  engines are installed into %s\n\n' "$(eng_bindir)"
            ;;
        build|install)
            local target=${1:-}
            [ -n "$target" ] || die "which engine? try: pseudoforge engines build oncvpsp|uspp|fhi98pp|all"
            shift
            local yes=""
            case ${1:-} in -y|--yes) yes=--yes ;; esac
            if [ "$target" = all ]; then build_all "$yes"; else build_engine "$target" "$yes"; fi
            ;;
        show|info)
            local target=${1:-}
            [ -n "$target" ] || die "which engine?"
            eng_exists "$target" || die "unknown engine '$target'"
            printf '\n'; eng_describe "$target"; printf '\n'
            ;;
        path)
            local target=${1:-}
            eng_exists "$target" || die "unknown engine '$target'"
            eng_resolve "$target" || die "${ENG_LABEL[$target]} is not installed"
            ;;
        *) die "unknown subcommand '$sub' -- try: list, build, show, path" ;;
    esac
}

# ---------------------------------------------------------------------------
# pseudoforge citation <library>    print the reference for a library
# pseudoforge citation --all        every library PseudoForge knows
# ---------------------------------------------------------------------------
cmd_citation() {
    case "${1:-}" in -h|--help) cli_help_for citation; return 0 ;; esac
    local what=${1:-} id
    pf_metadata_load
    pf_profiles_load
    pf_engines_load

    case $what in
        ''|--all|all)
            banner "Citations"
            for id in $(prof_list_sorted); do
                printf '%s%s%s\n' "$C_BOLD" "${PROF_LABEL[$id]:-$id}" "$C_RESET"
                printf '  %s\n' "$(md_citation "$id")"
                printf '  licence: %s\n\n' "$(md_license "$id")"
            done
            printf '%sGenerator codes%s\n\n' "$C_BOLD" "$C_RESET"
            for id in $(eng_list); do
                printf '%s\n' "${ENG_LABEL[$id]:-$id}"
                # md_citation_set expands MD_ALSO_CITE, so a distribution
                # that asks for three papers gets three lines, not one.
                for ref in $(md_citation_set "$id"); do
                    [ "$ref" = pseudoforge ] && continue
                    printf '  %s\n' "$(md_citation "$ref")"
                done
                printf '\n'
            done
            ;;
        *)
            if ! prof_exists "$what" && ! md_known "$what"; then
                die "unknown library '$what' -- try: pseudoforge list profiles, or pseudoforge citation --all"
            fi
            local engine=""
            prof_exists "$what" && engine=$(eng_for_profile "$what" "${SPEC[family]}")
            md_citation_text "$what" "$engine"
            ;;
    esac
}

# ---------------------------------------------------------------------------
# --attribution: a block ready to paste into a paper.
# ---------------------------------------------------------------------------
cli_print_attribution() {
    local prof=${SPEC[profile]} engine=${SPEC[engine]:-} id n=0
    pf_metadata_load
    pf_profiles_load

    printf 'Pseudopotentials were generated with PseudoForge %s using %s' \
           "$PSEUDOFORGE_VERSION" "${PROF_LABEL[$prof]:-$prof}"
    [ -n "$engine" ] && printf ' (%s)' "${ENG_LABEL[$engine]:-$engine}"
    printf ', with the %s exchange-correlation functional' "$(xc_qe_string "${SPEC[xc]}")"
    if ! xc_is_native "${SPEC[xc]}"; then
        printf ' as the semilocal parent for %s' "${XC_LABEL[${SPEC[xc]}]}"
    fi
    printf ', %s.\n\n' "$(lower "$(rel_label "${SPEC[rel]}")")"

    printf 'References:\n'
    while read -r id; do
        [ -n "$id" ] || continue
        n=$((n + 1))
        printf '  [%d] %s\n' "$n" "$(md_citation "$id")"
    done < <(md_citation_set "$prof" "$engine")
    [ "$n" = 0 ] && printf '  (PseudoForge has no verified citation for this selection -- check the source)\n'
    printf '\n'
}

# ---------------------------------------------------------------------------
# pseudoforge params [status|fetch <library>|path <library>]
#
# The generation inputs published by the libraries themselves.  Holding these
# is what makes a run a reproduction rather than an approximation.
# ---------------------------------------------------------------------------
cmd_params() {
    case "${1:-}" in -h|--help)
        cat <<'XC_EOF'
usage: pseudoforge params <sub> [args]

Subcommands:
  status [LIB]     what inputs are held, what can be fetched
  fetch <LIB>      download a library's published generation inputs
  path <LIB>       print where a library's inputs live
  extract <DIR> [LIB]   recover generation decks from published UPF files
XC_EOF
        return 0 ;;
    esac
    local sub=${1:-status}; [ $# -gt 0 ] && shift
    case "${1:-}" in
        -h|--help)
            case $sub in
                status|list) printf 'usage: pseudoforge params status [LIB]\n' ;;
                fetch|get)   printf 'usage: pseudoforge params fetch <LIB> [elements]\n' ;;
                path)        printf 'usage: pseudoforge params path <LIB>\n' ;;
                extract)     printf 'usage: pseudoforge params extract <dir-of-upf> [LIB]\n' ;;
                *)           printf 'usage: pseudoforge params status|fetch|path|extract\n' ;;
            esac
            return 0 ;;
    esac
    pf_params_load
    pf_profiles_load
    case $sub in
        extract)
            # Recover a library's real generation decks from files it published.
            local dir=${1:-} lib=${2:-${SPEC[profile]}}
            [ -n "$dir" ] || die "usage: pseudoforge params extract <dir-of-upf> [library]"
            params_extract_dir "$dir" "$lib" ;;
        status|list|"")
            banner "Published generation inputs"
            printf '  %-14s %-11s %s\n' LIBRARY KIND STATUS
            printf '  %-14s %-11s %s\n' "--------------" "-----------" "------"
            params_status
            printf '\n  cache: %s\n' "$(params_root)"
            printf '  fetch: pseudoforge params fetch <library>\n\n'
            ;;
        fetch|get)
            local lib=${1:-}
            [ -n "$lib" ] || die "which library? try: pseudoforge params status"
            shift
            [ $# -gt 0 ] && PARAMS_ELEMENTS="$*"
            params_fetch "$lib"
            ;;
        path)
            local lib=${1:-}
            [ -n "$lib" ] || die "which library?"
            params_dir "$lib"
            ;;
        *) die "unknown subcommand '$sub' -- try: status, fetch, path" ;;
    esac
}

# ---------------------------------------------------------------------------
# pseudoforge profile new|edit|list|remove
#
# Profiles are key=value files, so anyone can add one.  These commands save you
# looking up the field names, and validate what you write before it reaches a
# generation run.  User profiles live outside the installation so that updating
# PseudoForge cannot overwrite them.
# ---------------------------------------------------------------------------
cmd_profile() {
    case "${1:-}" in -h|--help)
        cat <<'XC_EOF'
usage: pseudoforge profile <sub> [args]

Subcommands:
  list             every profile, shipped and user
  new <id>         create a user profile
  edit <id>        edit a user profile
  remove <id>      remove a user profile

User profiles live in $HOME/.pseudoforge/profiles and override shipped
ones of the same name.
XC_EOF
        return 0 ;;
    esac
    local sub=${1:-list}; [ $# -gt 0 ] && shift
    case "${1:-}" in
        -h|--help)
            case $sub in
                list)   printf 'usage: pseudoforge profile list\n' ;;
                new)    printf 'usage: pseudoforge profile new <id> [--label ... --families ... --engine ...]\n' ;;
                edit)   printf 'usage: pseudoforge profile edit <id>\n' ;;
                remove) printf 'usage: pseudoforge profile remove <id>\n' ;;
                *)      printf 'usage: pseudoforge profile list|new|edit|remove\n' ;;
            esac
            return 0 ;;
    esac
    pf_profiles_load
    local udir=${PF_USER_DATA:-$HOME/.pseudoforge}/profiles
    case $sub in
        list|"")
            banner "Profiles"
            local id
            for id in $(prof_list_sorted); do
                printf '  %-14s %-13s %-9s %s\n' "$id" "$(prof_badge "$id")" \
                    "${PROF_FAMILIES[$id]}" "${PROF_LABEL[$id]}"
            done
            printf '\n  user profiles: %s\n' "$udir"
            printf '  new: pseudoforge profile new <id> --label "..." --families "nc us" --engine oncvpsp\n\n'
            ;;
        new|create)
            local id=${1:-}
            [ -n "$id" ] || die "pseudoforge profile new <id> [options]"
            case $id in
                *[!a-zA-Z0-9._-]*) die "a profile id may contain only letters, digits, dot, dash and underscore" ;;
            esac
            prof_exists "$id" && die "profile '$id' already exists -- see: pseudoforge show $id"
            shift

            local label=$id families=paw engine=ld1 setpaw='' setus='' setnc=''
            local summary='' notes='' license='' reference='' author=''
            while [ $# -gt 0 ]; do
                case $1 in
                    --label)     label=${2:?}; shift 2 ;;
                    --families)  families=${2:?}; shift 2 ;;
                    --engine)    engine=${2:?}; shift 2 ;;
                    --set-paw)   setpaw=${2:?}; shift 2 ;;
                    --set-us)    setus=${2:?}; shift 2 ;;
                    --set-nc)    setnc=${2:?}; shift 2 ;;
                    --summary)   summary=${2:?}; shift 2 ;;
                    --notes)     notes=${2:?}; shift 2 ;;
                    --license)   license=${2:?}; shift 2 ;;
                    --reference) reference=${2:?}; shift 2 ;;
                    --author)    author=${2:?}; shift 2 ;;
                    *) die "unknown option '$1'" ;;
                esac
            done
            eng_exists "$engine" || die "unknown engine '$engine' -- try: pseudoforge engines list"

            mkdir -p "$udir" || die "cannot create $udir"
            local f=$udir/$id.profile
            {
                printf '# Created by %s %s on %s\n' "$PSEUDOFORGE_NAME" "$PSEUDOFORGE_VERSION" "$(date '+%Y-%m-%d')"
                printf 'id=%s\n' "$id"
                printf 'label=%s\n' "$label"
                printf 'families=%s\n' "$families"
                printf 'engine=%s\n' "$engine"
                printf 'provenance=derived\n'
                printf 'generator=%s\n' "$engine"
                [ -n "$setpaw" ] && printf 'set_paw=%s\n' "$setpaw"
                [ -n "$setus" ]  && printf 'set_us=%s\n'  "$setus"
                [ -n "$setnc" ]  && printf 'set_nc=%s\n'  "$setnc"
                printf 'summary=%s\n' "${summary:-A profile defined locally.}"
                printf 'notes=%s\n' "${notes:-Created locally; not a published library. Validate before relying on it.}"
                [ -n "$license" ]   && printf 'license=%s\n' "$license"
                [ -n "$reference" ] && printf 'reference=%s\n' "$reference"
                [ -n "$author" ]    && printf 'author=%s\n' "$author"
                true
            } > "$f" || die "cannot write $f"

            ok "wrote $f"
            info "check it with: pseudoforge show $id"
            ;;
        edit)
            local id=${1:-}
            [ -n "$id" ] || die "pseudoforge profile edit <id>"
            local f=$udir/$id.profile
            [ -f "$f" ] || f=$PF_DATA/profiles/$id.profile
            [ -f "$f" ] || die "no such profile: $id"
            case $f in
                "$PF_DATA"/*)
                    mkdir -p "$udir"
                    cp -n "$f" "$udir/$id.profile"
                    warn "copied the shipped profile into $udir so your edits survive an update"
                    f=$udir/$id.profile ;;
            esac
            "${EDITOR:-vi}" "$f"
            ;;
        remove|rm)
            local id=${1:-}
            [ -n "$id" ] || die "pseudoforge profile remove <id>"
            [ -f "$udir/$id.profile" ] || die "'$id' is not a user profile; shipped profiles are not removed"
            rm -f "$udir/$id.profile" && ok "removed $id"
            ;;
        *) die "unknown subcommand '$sub' -- try: list, new, edit, remove" ;;
    esac
}

# ---------------------------------------------------------------------------
# pseudoforge xc add|list|remove
#
# The functional registry is a TSV and the same reasoning applies: adding one
# should not mean editing a file that the next update overwrites.
# ---------------------------------------------------------------------------
cmd_xc() {
    case "${1:-}" in -h|--help)
        cat <<'XC_EOF'
usage: pseudoforge xc <sub> [args]

Subcommands:
  list             every functional, with its family and status
  add <id>         add a user functional
  remove <id>      remove a user functional

User functionals live in $HOME/.pseudoforge/xc.tsv.
XC_EOF
        return 0 ;;
    esac
    local sub=${1:-list}; [ $# -gt 0 ] && shift
    case "${1:-}" in
        -h|--help)
            case $sub in
                list)   printf 'usage: pseudoforge xc list\n' ;;
                add)    printf 'usage: pseudoforge xc add <id> --qe <DFT-STRING> [--family ... --label ...]\n' ;;
                remove) printf 'usage: pseudoforge xc remove <id>\n' ;;
                *)      printf 'usage: pseudoforge xc list|add|remove\n' ;;
            esac
            return 0 ;;
    esac
    pf_xc_load
    local ufile=${PF_USER_DATA:-$HOME/.pseudoforge}/xc.tsv
    case $sub in
        list|"")
            banner "Functionals"
            local id
            for id in "${XC_ORDER[@]}"; do
                printf '  %-14s %-9s %-8s %s\n' "$id" "${XC_FAMILY[$id]}" \
                    "${XC_STATUS[$id]}" "${XC_LABEL[$id]}"
            done
            printf '\n  user functionals: %s\n' "$ufile"
            printf '  add: pseudoforge xc add <id> --qe <DFT-STRING> --family GGA --label "..."\n\n'
            ;;
        add|new)
            local id=${1:-}
            [ -n "$id" ] || die "pseudoforge xc add <id> --qe <DFT-STRING> [options]"
            shift
            id=$(lower "$id")
            xc_exists "$id" && die "functional '$id' already exists"

            local qe='' fam=GGA label='' status=native proxy=- note='' tag=$id
            while [ $# -gt 0 ]; do
                case $1 in
                    --qe|--dft) qe=${2:?}; shift 2 ;;
                    --family)   fam=${2:?}; shift 2 ;;
                    --label)    label=${2:?}; shift 2 ;;
                    --tag)      tag=${2:?}; shift 2 ;;
                    --proxy)    proxy=$(lower "${2:?}"); status=proxy; shift 2 ;;
                    --note)     note=${2:?}; shift 2 ;;
                    *) die "unknown option '$1'" ;;
                esac
            done
            [ -n "$qe" ] || die "--qe is required: the string the atomic code receives as dft="
            case $fam in
                LDA|GGA|metaGGA|hybrid|vdW) ;;
                *) die "--family must be one of: LDA GGA metaGGA hybrid vdW" ;;
            esac
            if [ "$status" = proxy ]; then
                xc_exists "$proxy" || die "--proxy '$proxy' is not a known functional"
            fi

            mkdir -p "$(dirname "$ufile")" || die "cannot create $(dirname "$ufile")"
            if [ ! -f "$ufile" ]; then
                printf '#id\ttag\tqe_dft\tfamily\tlabel\tstatus\tproxy\tnote\n' > "$ufile"
            fi
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                "$id" "$tag" "$qe" "$fam" "${label:-$id}" "$status" "$proxy" \
                "${note:-Added locally.}" >> "$ufile"
            ok "added '$id' to $ufile"
            info "check it with: pseudoforge recipe Si -x $id"
            ;;
        remove|rm)
            local id=${1:-}
            [ -n "$id" ] || die "pseudoforge xc remove <id>"
            [ -f "$ufile" ] || die "no user functionals are defined"
            grep -q "^$id$(printf '\t')" "$ufile" || die "'$id' is not a user functional"
            grep -v "^$id$(printf '\t')" "$ufile" | write_atomic "$ufile"
            ok "removed $id"
            ;;
        *) die "unknown subcommand '$sub' -- try: list, add, remove" ;;
    esac
}


# ---------------------------------------------------------------------------
# pseudoforge compare <a.UPF> <b.UPF> [--ecut N]
#
# Answers "is my locally generated file the same as the published one?", which
# a byte comparison cannot: different generator versions write different radial
# grids for identical physics.
# ---------------------------------------------------------------------------
cmd_compare() {
    case "${1:-}" in -h|--help)
        cat <<'CMP_EOF'
usage: pseudoforge compare <a> <b> [--ecut N] [--diff] [--json]

Compare two pseudopotentials.  Both files are read, their log derivatives
are computed and drawn side by side, and the differences in cutoff
convergence are reported.

CMP_EOF
        return 0 ;;
    esac
    local a=${1:-} b=${2:-} ecut="" mode_diff=0 mode_json=0
    [ -n "$a" ] && [ -n "$b" ] || die "usage: pseudoforge compare <a.UPF> <b.UPF> [--ecut N] [--diff] [--json]"
    shift 2
    while [ $# -gt 0 ]; do
        case $1 in
            --ecut) ecut=$2; shift 2 ;;
            --diff|--meta) mode_diff=1; shift ;;
            --json) mode_json=1; shift ;;
            *) die "unknown option '$1'" ;;
        esac
    done

    if [ "$mode_json" = 1 ]; then
        compare_for "$a" "$b" || die "could not compare $a and $b"
        compare_render_json
        return 0
    fi

    if [ "$mode_diff" = 1 ] || ! deps_have_pw; then
        compare_for "$a" "$b" || die "could not compare $a and $b"
        compare_render_human
        return 0
    fi

    deps_resolve_qe
    banner "Comparing"
    cmp_pseudos "$a" "$b" "$ecut"
    local rc=$?
    cmp_report "$a" "$b"
    return $rc
}

# ---------------------------------------------------------------------------
# cmd_recipe_store -- the saved-recipe subcommands.
#
# `pseudoforge recipe <element>` already meant "show me the deck for this
# element", and it still does.  The subcommands below are recognised first;
# none of them is an element symbol, so the two senses of the word cannot
# collide.  tests/test_recipe_roundtrip.sh asserts that.
# ---------------------------------------------------------------------------
cmd_recipe_store() {
    case "${1:-}" in
        -h|--help|'')
            cat <<'RCP_EOF'
usage: pseudoforge recipe save <name> [options]
       pseudoforge recipe load <name>
       pseudoforge recipe show <name>
       pseudoforge recipe list
       pseudoforge recipe delete <name>
       pseudoforge recipe export <name> [file]
       pseudoforge recipe import <file> [name]
       pseudoforge recipe path [name]
RCP_EOF
            return 0 ;;
    esac
    local sub=${1:-}; shift || true
    case "${1:-}" in
        -h|--help)
            case $sub in
                save)   printf 'usage: pseudoforge recipe save <name> [options] [--description DESC]\n' ;;
                load)   printf 'usage: pseudoforge recipe load <name>\n' ;;
                show)   printf 'usage: pseudoforge recipe show <name>\n' ;;
                list|ls) printf 'usage: pseudoforge recipe list\n' ;;
                delete|rm) printf 'usage: pseudoforge recipe delete <name>\n' ;;
                export) printf 'usage: pseudoforge recipe export <name> [file]\n' ;;
                import) printf 'usage: pseudoforge recipe import <file> [name]\n' ;;
                path)   printf 'usage: pseudoforge recipe path [name]\n' ;;
                *)      printf 'usage: pseudoforge recipe save|load|show|list|delete|export|import|path\n' ;;
            esac
            return 0 ;;
    esac
    case $sub in
        save)
            local name=${1:-}; shift || true
            [ -n "$name" ] || die "usage: pseudoforge recipe save <name> [options]"
            local desc=
            # A --description is for the saved file only; everything else is
            # the specification being saved.
            local args=() a
            while [ $# -gt 0 ]; do
                case $1 in
                    --description|--desc) desc=$2; shift 2 ;;
                    *) args+=("$1"); shift ;;
                esac
            done
            cli_parse "${args[@]}"
            cli_check_spec
            local f; f=$(rcp_save "$name" "$desc") || exit 1
            ok "saved $name"
            info "  $f"
            info "  reuse with: pseudoforge generate --recipe $name"
            ;;

        load|show)
            local name=${1:-}
            [ -n "$name" ] || die "usage: pseudoforge recipe $sub <name>"
            rcp_load "$name" || exit 1
            if [ "$sub" = show ]; then
                banner "recipe: $name"
                sed 's/^/  /' "$RCP_LOADED"
            fi
            printf '\n'
            info "equivalent command:"
            printf '  %s\n' "$(spec_cmdline)"
            ;;

        list|ls)
            local rows; rows=$(rcp_list)
            if [ -z "$rows" ]; then
                info "no saved recipes yet"
                info "  save one with: pseudoforge recipe save <name> -e Si -t paw"
                return 0
            fi
            banner "saved recipes"
            printf '  %-20s %-34s %s\n' NAME ELEMENTS DESCRIPTION
            printf '%s\n' "$rows" | while IFS=$'\t' read -r n els d; do
                [ ${#els} -gt 33 ] && els="${els:0:30}..."
                printf '  %-20s %-34s %s\n' "$n" "$els" "$d"
            done
            ;;

        delete|rm)
            local name=${1:-}
            [ -n "$name" ] || die "usage: pseudoforge recipe delete <name>"
            local f; f=$(rcp_delete "$name") || exit 1
            ok "deleted $name"
            ;;

        export)
            local name=${1:-} dest=${2:-}
            [ -n "$name" ] || die "usage: pseudoforge recipe export <name> [file]"
            local src; src=$(rcp_path "$name") || die "bad recipe name: $name"
            [ -f "$src" ] || die "no such recipe: $name"
            if [ -z "$dest" ] || [ "$dest" = - ]; then
                cat "$src"
            else
                cp "$src" "$dest" || die "cannot write $dest"
                ok "exported $name"
                info "  $dest"
            fi
            ;;

        import)
            local src=${1:-} name=${2:-}
            [ -n "$src" ] || die "usage: pseudoforge recipe import <file> [name]"
            [ -f "$src" ] || die "no such file: $src"
            # Load it first: a file that will not load must not be filed away
            # as though it were usable.
            rcp_load "$src" || exit 1
            [ -n "$name" ] || name=$(basename "$src" .recipe)
            local dest; dest=$(rcp_path "$name") || die "bad recipe name: $name"
            if [ -f "$dest" ]; then
                pf_confirm "overwrite the existing recipe '$name'?" || { info "kept the existing one"; return 0; }
            fi
            cp "$src" "$dest" || die "cannot write $dest"
            ok "imported as $name"
            info "  $dest"
            info "  use with: pseudoforge generate --recipe $name"
            ;;

        path)
            rcp_dir
            ;;

        *)
            die "unknown: pseudoforge recipe $sub  (save load show list delete export import path)"
            ;;
    esac
}

# ---------------------------------------------------------------------------
# cmd_api -- the REST interface from the command line.
#
#   pseudoforge api GET /api/engines
#   pseudoforge api POST /api/convert body.json
#   pseudoforge api --routes
#
# The HTTP server calls exactly this. Everything about routing, response
# shapes and refusals lives in lib/http.sh, so the server has nothing to
# reimplement -- it moves bytes and a status code.
#
# The status goes to stderr as "status: NNN" rather than into the body, so a
# caller can read the JSON on stdout without stripping anything out of it.
# ---------------------------------------------------------------------------
cmd_api() {
    local method="" path="" body="" show_routes=0 status_only=0
    while [ $# -gt 0 ]; do
        case $1 in
            --routes)  show_routes=1; shift ;;
            --status)  status_only=1; shift ;;
            -h|--help)
                printf 'usage: pseudoforge api <METHOD> <PATH> [body-file]\n'
                printf '       pseudoforge api --routes\n'
                return 0 ;;
            -*)        die "unknown option: $1" ;;
            *)
                if   [ -z "$method" ]; then method=$1
                elif [ -z "$path" ];   then path=$1
                else                        body=$1
                fi
                shift ;;
        esac
    done

    if [ "$show_routes" = 1 ]; then
        printf '%-6s %-24s %s\n' METHOD PATH SUMMARY
        local m p h sm
        while IFS=$'\t' read -r m p h sm; do
            printf '%-6s %-24s %s\n' "$m" "$p" "$sm"
        done < <(http_routes)
        return 0
    fi

    [ -n "$method" ] && [ -n "$path" ] \
        || die "usage: pseudoforge api <METHOD> <PATH> [body-file]"

    # Not a command substitution: that runs the handler in a subshell, and
    # HTTP_STATUS -- set by the handler -- would never come back. Every
    # response would be 200, including the refusals.
    local tmp; tmp=$(mktemp)
    http_handle "$(upper "$method")" "$path" "$body" > "$tmp"
    cat "$tmp"; rm -f "$tmp"
    printf 'status: %s\n' "$HTTP_STATUS" >&2

    [ "$status_only" = 1 ] && return 0
    # A 5xx is the server's fault and is worth a non-zero exit for scripts;
    # a 4xx is the caller's and is a perfectly good answer.
    case $HTTP_STATUS in 5*) return 1 ;; esac
    return 0
}

# ---------------------------------------------------------------------------
# cmd_native -- the native-file store the website serves from.
#
#   pseudoforge native index [dir]     rescan and rewrite index.tsv
#   pseudoforge native list [dir]      what is in the index
#   pseudoforge native size [dir]      the disk budget, per directory
# ---------------------------------------------------------------------------
cmd_native() {
    case "${1:-}" in -h|--help) cli_help_for native; return 0 ;; esac
    local sub=${1:-}; shift || true
    case "${1:-}" in
        -h|--help)
            case $sub in
                index) printf 'usage: pseudoforge native index [dir]\n' ;;
                list)  printf 'usage: pseudoforge native list [dir]\n' ;;
                size)  printf 'usage: pseudoforge native size [dir]\n' ;;
                *)     printf 'usage: pseudoforge native index|list|size [dir]\n' ;;
            esac
            return 0 ;;
    esac
    local dir=${1:-$PF_NATIVE_DIR}
    case $sub in
        index) native_index_build "$dir" ;;
        list)
            local idx=$dir/index.tsv
            [ -f "$idx" ] || die "no index at $idx -- run: pseudoforge native index"
            printf '%-30s %-4s %-8s %-5s %-6s %-10s %s\n' ID EL XC FAM FORMAT PROFILE SIZE
            awk -F'\t' '!/^#/ { printf "%-30s %-4s %-8s %-5s %-6s %-10s %s\n", $1, $2, $3, $4, $7, $8, $11 }' "$idx"
            ;;
        size)
            local root=${1:-$PF_VAR_DIR} total=0 d sz
            printf '%-14s %10s\n' DIRECTORY SIZE
            for d in native converter cache db docs www; do
                if [ -d "$root/$d" ]; then
                    sz=$(du -sk "$root/$d" 2>/dev/null | cut -f1)
                else
                    sz=0
                fi
                total=$((total + sz))
                printf '%-14s %9sM\n' "$d" "$((sz / 1024))"
            done
            printf '%-14s %9sM\n' TOTAL "$((total / 1024))"
            printf '%-14s %9sM\n' BUDGET "$((PF_VPS_BUDGET_MB))"
            if [ "$((total / 1024))" -gt "$PF_VPS_BUDGET_MB" ]; then
                error "over budget by $(( total / 1024 - PF_VPS_BUDGET_MB ))M"
                return 1
            fi
            ok "within the ${PF_VPS_BUDGET_MB}M budget"
            ;;
        '')
            printf 'usage: pseudoforge native index|list|size [dir]\n' ;;
        *) die "unknown: pseudoforge native $sub  (index list size)" ;;
    esac
}

# ---------------------------------------------------------------------------
# cmd_advise -- physics-reasoned pseudopotential recommendation
# ---------------------------------------------------------------------------
cmd_advise() {
    case "${1:-}" in -h|--help) cli_help_for advise; return 0 ;; esac
    local el="" calc="" code="" mat="" xc="" acc="" as_json=0 quiet=0
    while [ $# -gt 0 ]; do
        case $1 in
            -h|--help)
                cli_help_for advise; return 0 ;;
            -e|--element|--elements)
                [ $# -ge 2 ] || die "missing argument for $1"
                el=$2; shift 2 ;;
            --calculation|--calc)
                [ $# -ge 2 ] || die "missing argument for $1"
                calc=$2; shift 2 ;;
            --code)
                [ $# -ge 2 ] || die "missing argument for $1"
                code=$2; shift 2 ;;
            --material)
                [ $# -ge 2 ] || die "missing argument for $1"
                mat=$2; shift 2 ;;
            --functional|-x)
                [ $# -ge 2 ] || die "missing argument for $1"
                xc=$2; shift 2 ;;
            --accuracy)
                [ $# -ge 2 ] || die "missing argument for $1"
                acc=$2; shift 2 ;;
            --json)
                as_json=1; shift ;;
            -q|--quiet)
                quiet=1; shift ;;
            *)
                if [ -z "$el" ] && [[ "$1" != -* ]]; then
                    el=$1; shift
                else
                    die "unknown option '$1' -- try: pseudoforge advise --help"
                fi ;;
        esac
    done

    [ -n "$el" ] || die "usage: pseudoforge advise -e <element> [options] -- try: pseudoforge advise --help"

    advise_for "$el" "$calc" "$code" "$mat" "$xc" "$acc" || return 1

    if [ "$as_json" -eq 1 ]; then
        advise_render_json
    else
        advise_render_human "$quiet"
    fi
}

# ---------------------------------------------------------------------------
# cmd_provenance -- show provenance record for a native file
# ---------------------------------------------------------------------------
cmd_provenance() {
    case "${1:-}" in -h|--help) cli_help_for provenance; return 0 ;; esac
    local id="" as_json=0
    while [ $# -gt 0 ]; do
        case $1 in
            -h|--help)
                cli_help_for provenance; return 0 ;;
            --json)
                as_json=1; shift ;;
            *)
                if [ -z "$id" ] && [[ "$1" != -* ]]; then
                    id=$1; shift
                else
                    die "unknown option '$1' -- try: pseudoforge provenance --help"
                fi ;;
        esac
    done

    [ -n "$id" ] || die "usage: pseudoforge provenance <id> [--json] -- try: pseudoforge provenance --help"

    provenance_for "$id" || exit 1

    if [ "$as_json" -eq 1 ]; then
        provenance_render_json
    else
        provenance_render_human
    fi
}

# ---------------------------------------------------------------------------
# cmd_element -- show files and available profiles for an element
# ---------------------------------------------------------------------------
cmd_element() {
    case "${1:-}" in -h|--help) cli_help_for element; return 0 ;; esac
    local sym="" as_json=0
    while [ $# -gt 0 ]; do
        case $1 in
            -h|--help)
                cli_help_for element; return 0 ;;
            --json)
                as_json=1; shift ;;
            *)
                if [ -z "$sym" ] && [[ "$1" != -* ]]; then
                    sym=$1; shift
                else
                    die "unknown option '$1' -- try: pseudoforge element --help"
                fi ;;
        esac
    done

    [ -n "$sym" ] || die "usage: pseudoforge element <symbol> [--json] -- try: pseudoforge element --help"

    element_summary_for "$sym" || exit 1

    if [ "$as_json" -eq 1 ]; then
        element_render_json
    else
        element_render_human
    fi
}

# ---------------------------------------------------------------------------
# cmd_coverage -- matrix of element x profile availability
# ---------------------------------------------------------------------------
cmd_coverage() {
    case "${1:-}" in -h|--help) cli_help_for coverage; return 0 ;; esac
    local prof="" el="" as_json=0
    while [ $# -gt 0 ]; do
        case $1 in
            -h|--help)
                cli_help_for coverage; return 0 ;;
            --profile|-p)
                [ $# -ge 2 ] || die "missing argument for $1"
                prof=$2; shift 2 ;;
            --element|-e)
                [ $# -ge 2 ] || die "missing argument for $1"
                el=$2; shift 2 ;;
            --json)
                as_json=1; shift ;;
            *)
                die "unknown option '$1' -- try: pseudoforge coverage --help" ;;
        esac
    done

    coverage_matrix "$prof" "$el" || exit 1

    if [ "$as_json" -eq 1 ]; then
        coverage_render_json
    else
        coverage_render_human
    fi
}

# ---------------------------------------------------------------------------
# cmd_recent -- show most recently added files
# ---------------------------------------------------------------------------
cmd_recent() {
    case "${1:-}" in -h|--help) cli_help_for recent; return 0 ;; esac
    local count=10 as_json=0
    while [ $# -gt 0 ]; do
        case $1 in
            -h|--help)
                cli_help_for recent; return 0 ;;
            --count|-n)
                [ $# -ge 2 ] || die "missing argument for $1"
                count=$2; shift 2 ;;
            --json)
                as_json=1; shift ;;
            [0-9]*)
                count=$1; shift ;;
            *)
                die "unknown option '$1' -- try: pseudoforge recent --help" ;;
        esac
    done

    recent_files "$count" || exit 1

    if [ "$as_json" -eq 1 ]; then
        recent_render_json
    else
        recent_render_human "$count"
    fi
}

# ---------------------------------------------------------------------------
# cmd_capabilities -- show capability matrix across deployment tiers
# ---------------------------------------------------------------------------
cmd_capabilities() {
    case "${1:-}" in -h|--help) cli_help_for capabilities; return 0 ;; esac
    local as_json=0
    while [ $# -gt 0 ]; do
        case $1 in
            -h|--help)
                cli_help_for capabilities; return 0 ;;
            --json)
                as_json=1; shift ;;
            *)
                die "unknown option '$1' -- try: pseudoforge capabilities --help" ;;
        esac
    done

    capabilities_for || exit 1

    if [ "$as_json" -eq 1 ]; then
        capabilities_render_json
    else
        capabilities_render_human
    fi
}

# ---------------------------------------------------------------------------
# cmd_cutoff -- recommended kinetic-energy cutoff for an element
# ---------------------------------------------------------------------------
cmd_cutoff() {
    case "${1:-}" in -h|--help) cli_help_for cutoff; return 0 ;; esac
    local el="" acc="efficiency" xc="PBE" proj="" as_json=0
    while [ $# -gt 0 ]; do
        case $1 in
            -h|--help)
                cli_help_for cutoff; return 0 ;;
            --element|-e)
                [ $# -ge 2 ] || die "missing argument for $1"
                el=$2; shift 2 ;;
            --accuracy|-a)
                [ $# -ge 2 ] || die "missing argument for $1"
                acc=$2; shift 2 ;;
            --xc|-x)
                [ $# -ge 2 ] || die "missing argument for $1"
                xc=$2; shift 2 ;;
            --project|-o)
                [ $# -ge 2 ] || die "missing argument for $1"
                proj=$2; shift 2 ;;
            --json)
                as_json=1; shift ;;
            *)
                if [ -z "$el" ] && [[ "$1" != -* ]]; then
                    el=$1; shift
                else
                    die "unknown option '$1' -- try: pseudoforge cutoff --help"
                fi ;;
        esac
    done

    [ -n "$el" ] || die "element required: use -e/--element <symbol>"
    cutoff_for "$el" "$acc" "$xc" "$proj" || die "no recommended cutoff found for $el ($acc, $xc)"

    if [ "$as_json" -eq 1 ]; then
        cutoff_render_json
    else
        cutoff_render_human
    fi
}
