# shellcheck shell=bash
# ---------------------------------------------------------------------------
# engines.sh -- the generator-engine registry.
#
# PseudoForge drives nine independent atomic codes.  Each owns a different corner
# of pseudopotential space, and none can produce what another produces:
#
#   ld1       Quantum ESPRESSO's atomic code.  NC / US / PAW.  Writes UPF
#             directly.  The engine behind every psl-* profile.
#   oncvpsp   Hamann's optimised norm-conserving Vanderbilt generator.  NC
#             only, multi-projector.  Writes UPF directly.  The engine behind
#             SG15 and PseudoDojo's NC tables.
#   uspp      Vanderbilt's ultrasoft generator.  US only.  Writes its own
#             format; converted to UPF with QE's upfconv.x.
#   fhi98pp   Fuchs/Scheffler's generator.  NC (Hamann or Troullier-Martins).
#             Writes .cpi/.fhi; converted to UPF with QE's upfconv.x.
#   opium     The Rappe group's generator.  NC, and the widest format range.
#   gth       Goedecker-Teter-Hutter.  Two programs rather than one: atom.x
#             solves the all-electron atom, pseudo.x fits the analytic GTH
#             form to it.  Unlike every other engine here the output is not a
#             tabulated radial function but a handful of coefficients, which
#             is why a GTH pseudopotential fits on one line of a paper.
#   atompaw   Holzwarth's PAW generator.  The only engine here besides ld1 that
#             makes PAW data sets, and the only one that writes them for ABINIT
#             and the PAW-XML schema as well as for Quantum ESPRESSO.
#   ape       The Atomic Pseudopotential Engine.  Norm-conserving, and the
#             only engine here that takes libxc functional names directly --
#             which is what lets it reach functionals no other engine can.
#   adpack    Ozaki's atomic code for OpenMX.  Norm-conserving (TM, BHS, MBK),
#             writing OpenMX .vps and .pao files.
#
# IMPORTANT, and the reason this file is careful about its wording: owning the
# engine is not the same as owning the parameters.  What makes SG15 "SG15" is
# its table of cut-off radii, q-cutoffs and projector counts -- not the fact
# that ONCVPSP produced it.  PseudoForge therefore never invents those numbers.
# It uses parameters published by the library itself (fetched or supplied),
# parameters shipped inside the engine's own source tree, or its own clearly
# labelled construction.  See docs/reference/data-provenance.md.
# ---------------------------------------------------------------------------

declare -gA ENG_LABEL ENG_FAMILIES ENG_BIN_VAR ENG_BINARIES ENG_SRC ENG_UPSTREAM \
            ENG_LICENSE ENG_NATIVE_UPF ENG_NOTE
declare -ga ENG_ORDER=(ld1 oncvpsp uspp fhi98pp opium gth atompaw ape adpack)

pf_engines_load() {
    [ -n "${ENG_LABEL[ld1]:-}" ] && return 0

    ENG_LABEL[ld1]="Quantum ESPRESSO ld1.x"
    ENG_FAMILIES[ld1]="nc us paw"
    ENG_BIN_VAR[ld1]="LD1_BIN"
    ENG_BINARIES[ld1]="ld1.x"
    ENG_SRC[ld1]=""
    ENG_UPSTREAM[ld1]="https://gitlab.com/QEF/q-e"
    ENG_LICENSE[ld1]="GPL-2.0-or-later"
    ENG_NATIVE_UPF[ld1]=yes
    ENG_NOTE[ld1]="Ships with Quantum ESPRESSO. The only engine here that covers all three families (NC, US and PAW), and the engine behind every psl-* profile."

    ENG_LABEL[oncvpsp]="ONCVPSP (Hamann)"
    ENG_FAMILIES[oncvpsp]="nc"
    ENG_BIN_VAR[oncvpsp]="ONCVPSP_BIN"
    ENG_BINARIES[oncvpsp]="oncvpsp.x oncvpspnr.x oncvpspr.x"
    ENG_SRC[oncvpsp]="oncvpsp-master.zip"
    ENG_UPSTREAM[oncvpsp]="https://github.com/oncvpsp/oncvpsp"
    ENG_LICENSE[oncvpsp]="GPL-3.0"
    ENG_NATIVE_UPF[oncvpsp]=yes
    ENG_NOTE[oncvpsp]="Three binaries: oncvpsp.x scalar-relativistic, oncvpspnr.x non-relativistic, oncvpspr.x full-relativistic. Writes UPF when psfile=upf. Built against libxc it accepts a negative iexc naming any libxc LDA or GGA pair, which adds PBEsol, BLYP, revPBE, WC, PW91 and AM05 to the four built-ins. It does NOT add meta-GGA: libxc has SCAN, but ONCVPSP functionals.F90 stops at XC_FAMILY_MGGA with \"meta GGA not coded yet\", so SCAN and r2SCAN remain out of reach whatever libxc is linked. Without libxc it offers only PZ and PBE."

    ENG_LABEL[uspp]="USPP (Vanderbilt)"
    ENG_FAMILIES[uspp]="us"
    ENG_BIN_VAR[uspp]="USPP_BIN"
    ENG_BINARIES[uspp]="runatom.x"
    ENG_SRC[uspp]="uspp-734-3.tgz"
    ENG_UPSTREAM[uspp]="https://www.physics.rutgers.edu/~dhv/uspp/"
    ENG_LICENSE[uspp]="GPL-2.0-or-later"
    ENG_NATIVE_UPF[uspp]=no
    ENG_NOTE[uspp]="Writes Vanderbilt .uspp files; PseudoForge converts them with QE's upfconv.x. Ships its own per-element input decks under Work/."

    ENG_LABEL[fhi98pp]="fhi98PP (Fuchs/Scheffler)"
    ENG_FAMILIES[fhi98pp]="nc"
    ENG_BIN_VAR[fhi98pp]="FHI98PP_BIN"
    ENG_BINARIES[fhi98pp]="fhipp.x pslp.x"
    ENG_SRC[fhi98pp]="fhi98PP.zip"
    ENG_UPSTREAM[fhi98pp]="https://th.fhi-berlin.mpg.de/th/fhi98md/fhi98PP/"
    ENG_LICENSE[fhi98pp]="see the licence inside the distribution"
    ENG_NATIVE_UPF[fhi98pp]=no
    ENG_NOTE[fhi98pp]="Hamann and Troullier-Martins norm-conserving schemes. Writes .cpi/.fhi; PseudoForge converts with upfconv.x. Ships a per-element parameter database under bin/Elements/{Ham,TM}."

    ENG_LABEL[opium]="OPIUM (Rappe group)"
    ENG_FAMILIES[opium]="nc"
    ENG_BIN_VAR[opium]="OPIUM_BIN"
    ENG_BINARIES[opium]="opium"
    ENG_SRC[opium]="opium-4.1.0.tar.gz"
    ENG_UPSTREAM[opium]="https://github.com/rappegroup/opium"
    ENG_LICENSE[opium]="GPL-2.0"
    ENG_NATIVE_UPF[opium]=yes
    ENG_NOTE[opium]="Norm-conserving, optimised (RRKJ) and Troullier-Martins. Writes UPF directly, and also FHI, CASTEP recpot, SIESTA, CPMD, CASINO, CHAMP, Teter and QSO -- the widest format range of any engine here. Functionals: pzlda, pwlda, pw91gga, pbegga, wcgga, pbesol. No meta-GGA and no hybrids -- no engine here has those. Hartree-Fock mode crashes in this build."

    ENG_LABEL[gth]="GTH (Goedecker/Hartwigsen, CP2K)"
    ENG_FAMILIES[gth]="nc"
    ENG_BIN_VAR[gth]="GTH_BIN"
    ENG_BINARIES[gth]="pseudo.x atom.x"
    ENG_SRC[gth]="cp2k-data.tar.gz"
    ENG_UPSTREAM[gth]="https://github.com/cp2k/cp2k-data"
    ENG_LICENSE[gth]="GPL-2.0-or-later"
    ENG_NATIVE_UPF[gth]=no
    ENG_NOTE[gth]="Two programs: atom.x solves the all-electron atom, pseudo.x fits the analytic GTH form to that solution by simplex minimisation. The result is a short coefficient table, not a radial grid, so it is written natively as CP2K, CPMD or ABINIT input rather than converted. Functionals: pade (LDA), pbe, pbesol, blyp, bp, olyp, hcth120, hcth407. Ships 435 published generation input sets."

    ENG_LABEL[atompaw]="AtomPAW (Holzwarth)"
    ENG_FAMILIES[atompaw]="paw"
    ENG_BIN_VAR[atompaw]="ATOMPAW_BIN"
    ENG_BINARIES[atompaw]="atompaw atompaw_aeonly"
    ENG_SRC[atompaw]="atompaw.tar.gz"
    ENG_UPSTREAM[atompaw]="https://github.com/atompaw/atompaw"
    ENG_LICENSE[atompaw]="GPL-3.0"
    ENG_NATIVE_UPF[atompaw]=yes
    ENG_NOTE[atompaw]="Projector-augmented-wave data sets. Until this engine, ld1.x was the only way PseudoForge could make PAW at all, and it writes only UPF; AtomPAW also writes the ABINIT format and the PAW-XML schema that GPAW and ABINIT read, from the same solve. Projector schemes: BLOECHL, VANDERBILT, MODRRKJ, VNCT and CUSTOM. It embeds its own input deck in the UPF PP_INFO block, so a dataset made with it can be reproduced from the file itself."

    ENG_LABEL[ape]="APE (Atomic Pseudopotential Engine)"
    ENG_FAMILIES[ape]="nc"
    ENG_BIN_VAR[ape]="APE_BIN"
    ENG_BINARIES[ape]="ape"
    ENG_SRC[ape]="ape.tar.gz"
    ENG_UPSTREAM[ape]="https://gitlab.com/ape/ape"
    ENG_LICENSE[ape]="GPL-2.0-or-later"
    ENG_NATIVE_UPF[ape]=yes
    ENG_NOTE[ape]="Norm-conserving, Troullier-Martins and Hamann schemes, writing UPF directly as well as SIESTA, Octopus and ABINIT formats. It needs GSL and libxc, both of which PseudoForge can build into its own prefix without root. Unlike every other engine here it names functionals by their libxc identifier rather than through a fixed table, so its functional range is libxc's range. It reads its deck from a file called inp.ape in the working directory -- not from a command-line argument, and not from standard input."

    ENG_LABEL[adpack]="ADPACK (Ozaki)"
    ENG_FAMILIES[adpack]="nc"
    ENG_BIN_VAR[adpack]="ADPACK_BIN"
    ENG_BINARIES[adpack]="adpack"
    ENG_SRC[adpack]="adpack2.2.tar.gz"
    ENG_UPSTREAM[adpack]="http://www.openmx-square.org/adpack/adpack.html"
    ENG_LICENSE[adpack]="GPL-2.0-or-later"
    ENG_NATIVE_UPF[adpack]=no
    ENG_NOTE[adpack]="Troullier-Martins, Bachelet-Hamann-Schlueter and MBK schemes, written for OpenMX. Writes .vps (OpenMX) and .pao; no UPF. Ships 29 per-element decks. Built from source by PseudoForge (see docs/reference/engines/adpack.md)."
}

# ---------------------------------------------------------------------------
# The manifest, and what it is for.
#
# data/engines.manifest records which version of each engine PseudoForge
# builds.  Until now nothing read it, which made it documentation that could
# drift from reality without anything noticing.  It is loaded here so that the
# version travels with the output.
#
# Why this matters more than it looks: "generated with ONCVPSP" is not a
# reproducible statement.  Two ONCVPSP builds a year apart, or one linked
# against libxc and one against the stub, produce different pseudopotentials
# from the same input.  Anyone trying to reproduce a published result needs to
# know which build, and the honest answer has two parts -- the version we
# meant to build, and a fingerprint of the binary that actually ran.
# ---------------------------------------------------------------------------
declare -gA ENG_VERSION ENG_URL ENG_SHA ENG_ARCHIVE
declare -g PF_MANIFEST_LOADED=

pf_manifest_load() {
    [ -n "$PF_MANIFEST_LOADED" ] && return 0
    local f=$PF_DATA/engines.manifest id ver url sha arch
    PF_MANIFEST_LOADED=1
    [ -f "$f" ] || return 0
    while IFS=$'\t' read -r id ver url sha arch; do
        case $id in ''|\#*) continue ;; esac
        ENG_VERSION[$id]=$ver
        ENG_URL[$id]=$url
        ENG_SHA[$id]=$sha
        ENG_ARCHIVE[$id]=$arch
    done < "$f"
}

# ---------------------------------------------------------------------------
# eng_build_id <engine>
#
# A short, stable fingerprint of the binary that will actually run.  sha256 of
# the executable, first 12 hex digits.
#
# This is used rather than asking each engine its version, because most of
# them will not say: fhi98PP answers an empty input with "STOP fhipp - verify
# input data file fort.22", the ultrasoft code dies on a Fortran read error,
# and neither prints a version at all.  A hash needs no cooperation, costs a
# few milliseconds, and distinguishes two builds of the same version -- which
# is the case that actually bites, since a libxc-linked ONCVPSP and a
# stub-linked one report the same version and are not the same program.
# ---------------------------------------------------------------------------
eng_build_id() {
    local bin
    bin=$(eng_resolve "$1" 2>/dev/null) || return 1
    [ -f "$bin" ] || return 1
    if have sha256sum; then
        sha256sum "$bin" 2>/dev/null | cut -c1-12
    elif have shasum; then
        shasum -a 256 "$bin" 2>/dev/null | cut -c1-12
    else
        return 1
    fi
}

# ---------------------------------------------------------------------------
# eng_provenance <engine> -- one line, for a report or a header.
#   "ONCVPSP (Hamann) 4.0.1 [build 1a2b3c4d5e6f] /path/to/oncvpsp.x"
# Each part is omitted rather than guessed when it is not known.
# ---------------------------------------------------------------------------
eng_provenance() {
    pf_engines_load; pf_manifest_load
    local eng=$1 ver bid bin out
    out=${ENG_LABEL[$eng]:-$eng}
    ver=${ENG_VERSION[$eng]:-}
    # ld1 is not in the manifest -- it ships inside Quantum ESPRESSO, so its
    # version is QE's and has to be asked for rather than looked up.
    [ -z "$ver" ] && [ "$eng" = ld1 ] && ver=$(deps_ld1_version 2>/dev/null)
    case $ver in unknown|'') ;; *) out="$out $ver" ;; esac
    bid=$(eng_build_id "$eng" 2>/dev/null) && out="$out [build $bid]"
    bin=$(eng_resolve "$eng" 2>/dev/null) && out="$out $bin"
    printf '%s\n' "$out"
}

# Every engine id, sorted.  The registry is the list; anything that prints
# engines -- the help text, the docs, the wizard -- reads it from here so a
# tenth engine cannot be added and left out of one of them.
eng_list()            { pf_engines_load; printf '%s
' "${!ENG_LABEL[@]}" | sort; }
eng_exists()          { pf_engines_load; [ -n "${ENG_LABEL[$1]:-}" ]; }
eng_supports_family() { pf_engines_load; in_list "$2" ${ENG_FAMILIES[$1]:-}; }

# Where PseudoForge keeps engines it built itself.
eng_prefix()   { printf '%s\n' "${ENGINE_DIR:-$HOME/.pseudoforge/engines}"; }
eng_bindir()   { printf '%s/bin\n'   "$(eng_prefix)"; }
eng_builddir() { printf '%s/build\n' "$(eng_prefix)"; }
eng_src_dir()  { printf '%s/src\n'   "$(eng_prefix)"; }

# ---------------------------------------------------------------------------
# eng_resolve <engine> -- find the engine's primary binary.
#
# Search order: the configured variable (which may name the binary or the
# directory holding it), then PseudoForge's own engine bin directory, then $PATH.
# Echoes the absolute path and updates the config variable so the rest of the
# run agrees with what was found.
# ---------------------------------------------------------------------------
eng_resolve() {
    pf_engines_load
    local eng=$1 var cand bin first
    var=${ENG_BIN_VAR[$eng]:-}
    [ -n "$var" ] || return 1
    first=${ENG_BINARIES[$eng]%% *}

    cand=${!var:-}
    if [ -n "$cand" ]; then
        if [ -f "$cand" ] && [ -x "$cand" ]; then printf '%s\n' "$cand"; return 0; fi
        if [ -d "$cand" ] && [ -x "$cand/$first" ]; then
            printf -v "$var" '%s' "$cand/$first"
            printf '%s\n' "$cand/$first"; return 0
        fi
    fi
    if [ -x "$(eng_bindir)/$first" ]; then
        printf -v "$var" '%s' "$(eng_bindir)/$first"
        printf '%s\n' "$(eng_bindir)/$first"; return 0
    fi
    if have "$first"; then
        bin=$(command -v "$first")
        printf -v "$var" '%s' "$bin"
        printf '%s\n' "$bin"; return 0
    fi
    return 1
}

eng_available() { eng_resolve "$1" >/dev/null 2>&1; }

# The specific binary for a relativity mode.  Only ONCVPSP splits them.
eng_binary_for_rel() {
    pf_engines_load
    local eng=$1 rel=$2 base dir
    base=$(eng_resolve "$eng") || return 1
    dir=$(dirname "$base")
    case $eng in
        oncvpsp)
            case $(rel_canon "$rel") in
                nonrel) printf '%s/oncvpspnr.x\n' "$dir" ;;
                full)   printf '%s/oncvpspr.x\n'  "$dir" ;;
                *)      printf '%s/oncvpsp.x\n'   "$dir" ;;
            esac ;;
        *) printf '%s\n' "$base" ;;
    esac
}

# ---------------------------------------------------------------------------
# eng_for_profile <profile> <family>
#
# A profile may name its engine explicitly (engine= in its .profile file);
# otherwise the family decides, with ld1 as the general-purpose default.
# ---------------------------------------------------------------------------
eng_for_profile() {
    pf_engines_load
    pf_profiles_load
    local prof=$1 fam=$2 e
    e=${PROF_ENGINE[$prof]:-}
    if [ -n "$e" ]; then printf '%s\n' "$e"; return 0; fi
    case $prof in
        psl-*|pseudoforge-auto) printf 'ld1\n'; return 0 ;;
    esac
    case $fam in
        paw) printf 'ld1\n' ;;
        us)  printf 'uspp\n' ;;
        nc)  printf 'oncvpsp\n' ;;
        *)   printf 'ld1\n' ;;
    esac
}

# ---------------------------------------------------------------------------
# eng_source_archive <engine> -- locate the source archive on disk.
#
# Looked for beside the PseudoForge script, in its parent (where the user dropped
# them), in the build directory, and in $PF_SRC_DIR if set.
# ---------------------------------------------------------------------------
eng_source_archive() {
    pf_engines_load
    local eng=$1 name d
    name=${ENG_SRC[$eng]:-}
    [ -n "$name" ] || return 1
    for d in "${PF_SRC_DIR:-}" "$PF_ROOT" "$PF_ROOT/.." "$(eng_src_dir)" "$(eng_builddir)" "$PWD"; do
        [ -n "$d" ] || continue
        [ -f "$d/$name" ] && { abspath "$d/$name"; return 0; }
    done
    return 1
}

# eng_status <engine> -> "<state>\t<detail>"
eng_status() {
    pf_engines_load
    local eng=$1 bin src
    if bin=$(eng_resolve "$eng" 2>/dev/null); then
        printf 'installed\t%s\n' "$bin"
    elif src=$(eng_source_archive "$eng" 2>/dev/null); then
        printf 'buildable\t%s\n' "$src"
    elif [ "$eng" = ld1 ]; then
        printf 'missing\tinstall Quantum ESPRESSO and set QE_ROOT_DIR\n'
    else
        printf 'missing\tno binary and no source archive found\n'
    fi
}

eng_describe() {
    pf_engines_load
    local eng=$1 state detail
    IFS=$'\t' read -r state detail < <(eng_status "$eng")
    printf '%s%s%s\n' "$C_BOLD" "${ENG_LABEL[$eng]}" "$C_RESET"
    printf '  families    : %s\n' "${ENG_FAMILIES[$eng]}"
    printf '  binaries    : %s\n' "${ENG_BINARIES[$eng]}"
    printf '  writes UPF  : %s\n' \
        "$([ "${ENG_NATIVE_UPF[$eng]}" = yes ] && echo "directly" || echo "via QE upfconv.x")"
    printf '  upstream    : %s\n' "${ENG_UPSTREAM[$eng]}"
    printf '  licence     : %s\n' "${ENG_LICENSE[$eng]}"
    printf '  status      : %s (%s)\n' "$state" "$detail"
    printf '\n  %s\n' "${ENG_NOTE[$eng]}"
}
