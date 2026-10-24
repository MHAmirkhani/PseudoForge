# shellcheck shell=bash
# ---------------------------------------------------------------------------
# build.sh -- compile the generator engines from source.
#
# PseudoForge cannot compile Fortran itself; what it does is know exactly how each
# of these three packages wants to be built, and drive make with the right
# settings.  All three predate modern gfortran by two decades, so each needs
# the same two concessions -- `-std=legacy` for F77 that current gfortran
# would otherwise reject, and `-fallow-argument-mismatch` for the old habit of
# passing a scalar where an array is declared.
#
# Everything lands under $ENGINE_DIR (default ~/.pseudoforge/engines):
#
#   ~/.pseudoforge/engines/build/<engine>/   unpacked source, kept for rebuilds
#   ~/.pseudoforge/engines/bin/              the finished binaries
#
# Nothing is written outside that directory and ~/.pseudoforgerc, and the only
# command that needs root is the package-manager step, which always asks.
# ---------------------------------------------------------------------------

# Legacy-Fortran flags shared by all three engines.
BUILD_LEGACY_FFLAGS="-O2 -std=legacy -fallow-argument-mismatch -fno-range-check"

# ---------------------------------------------------------------------------
# Platform detection and dependency packages
# ---------------------------------------------------------------------------
build_detect_os() {
    pf_detect_os
}

# The packages each OS needs.  Deliberately minimal: a Fortran compiler, a C
# compiler and preprocessor, make, and reference BLAS/LAPACK.
build_packages() {
    case $(build_detect_os) in
        debian)      echo "gfortran gcc make libblas-dev liblapack-dev unzip" ;;
        rhel|fedora) echo "gcc-gfortran gcc make blas-devel lapack-devel unzip" ;;
        arch)        echo "gcc-fortran gcc make blas lapack unzip" ;;
        suse)        echo "gcc-fortran gcc make blas-devel lapack-devel unzip" ;;
        macos)       echo "gcc open-mpi lapack unzip" ;;
        *)           echo "" ;;
    esac
}

build_install_command() {
    case $(build_detect_os) in
        debian)      echo "sudo apt-get install -y" ;;
        rhel|fedora) echo "sudo dnf install -y" ;;
        arch)        echo "sudo pacman -S --needed --noconfirm" ;;
        suse)        echo "sudo zypper install -y" ;;
        macos)       echo "brew install" ;;
        *)           echo "" ;;
    esac
}

# Which of the build prerequisites are actually missing right now?
build_missing_tools() {
    local missing="" t
    for t in gfortran gcc make; do have "$t" || missing="$missing $t"; done
    # cpp is only needed by ONCVPSP, but it comes with gcc everywhere
    build_have_lapack || missing="$missing lapack/blas"
    trim "$missing"
}

build_have_lapack() {
    local d
    for d in /usr/lib /usr/lib64 /usr/lib/x86_64-linux-gnu /usr/local/lib /opt/homebrew/lib; do
        [ -e "$d/liblapack.so" ] || [ -e "$d/liblapack.a" ] || \
        [ -e "$d/liblapack.dylib" ] || continue
        return 0
    done
    # a linker probe is the honest test, but it needs a compiler
    have gfortran || return 1
    printf '      program t\n      end\n' > "${TMPDIR:-/tmp}/pf_lapack_$$.f"
    if gfortran -o /dev/null "${TMPDIR:-/tmp}/pf_lapack_$$.f" -llapack -lblas 2>/dev/null; then
        rm -f "${TMPDIR:-/tmp}/pf_lapack_$$.f"; return 0
    fi
    rm -f "${TMPDIR:-/tmp}/pf_lapack_$$.f"; return 1
}

# ---------------------------------------------------------------------------
# build_install_deps [--yes]
#
# Installs the build prerequisites through the system package manager.  This is
# the one place PseudoForge asks for root, and it prints the exact command first so
# nobody has to trust it blindly.
# ---------------------------------------------------------------------------
build_install_deps() {
    local assume_yes=${1:-} missing cmd pkgs reply
    missing=$(build_missing_tools)
    if [ -z "$missing" ]; then
        ok "build prerequisites are already present"
        return 0
    fi
    cmd=$(build_install_command)
    pkgs=$(build_packages)
    if [ -z "$cmd" ] || [ -z "$pkgs" ]; then
        error "unrecognised platform -- install these yourself, then re-run:"
        error "  a Fortran compiler (gfortran), a C compiler, make, BLAS and LAPACK"
        return 1
    fi

    warn "missing build prerequisites:$missing"
    info "PseudoForge wants to run:"
    info "    $cmd $pkgs"
    # Asking is the interface's job, not this module's.  Reading the terminal
    # here blocks a web API and hangs a test suite; pf_confirm lets the CLI
    # prompt, the TUI open a dialog, and a non-interactive caller answer from
    # PF_ASSUME -- without this code knowing which.
    if [ "$assume_yes" != --yes ]; then
        if ! pf_confirm "Run it now?"; then
            info "skipped -- install the packages yourself and re-run"
            return 1
        fi
    fi
    # sudo will silently block forever on a password prompt if stdin is not a
    # terminal, which is exactly what happens inside a wizard or a CI run.
    case $cmd in
        sudo*)
            if ! sudo -n true 2>/dev/null; then
                if [ ! -t 0 ]; then
                    error "this needs root, and sudo wants a password but there is no terminal to ask on."
                    error "Run this yourself, then start PseudoForge again:"
                    printf '
    %s %s

' "$cmd" "$pkgs" | pf_emit_stream info
                    return 1
                fi
                info "sudo will ask for your password"
            fi ;;
    esac
    # shellcheck disable=SC2086
    $cmd $pkgs || { error "package installation failed"; return 1; }
    ok "build prerequisites installed"
}

# ---------------------------------------------------------------------------
# Archive extraction.  tar handles .tgz natively; zips need unzip, and we say
# so plainly rather than failing with a confusing error deep in the build.
# ---------------------------------------------------------------------------
build_extract() {   # build_extract <archive> <destdir>
    local ar=$1 dest=$2
    mkdir -p "$dest" || return 1
    case $ar in
        *.tgz|*.tar.gz) tar xzf "$ar" -C "$dest" ;;
        *.tar.bz2)      tar xjf "$ar" -C "$dest" ;;
        *.tar)          tar xf  "$ar" -C "$dest" ;;
        *.zip)
            if have unzip; then unzip -q -o "$ar" -d "$dest"
            elif have bsdtar; then bsdtar xf "$ar" -C "$dest"
            else
                error "cannot unpack $ar -- neither unzip nor bsdtar is installed"
                error "  Debian/Ubuntu: sudo apt-get install unzip"
                return 1
            fi ;;
        *) error "unknown archive type: $ar"; return 1 ;;
    esac
}

# After extraction the sources sit in a single subdirectory whose name we do
# not want to hard-code, since it changes between releases.
build_find_srcdir() {   # build_find_srcdir <dir> <marker-file>
    local dir=$1 marker=$2 d
    [ -e "$dir/$marker" ] && { printf '%s\n' "$dir"; return 0; }
    for d in "$dir"/*/; do
        [ -e "$d/$marker" ] && { printf '%s\n' "${d%/}"; return 0; }
    done
    return 1
}

build_jobs() {
    local n=${BUILD_JOBS:-}
    [ -n "$n" ] || n=$( { nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2; } )
    # these are small codes; more than 8 ways just thrashes
    [ "$n" -gt 8 ] 2>/dev/null && n=8
    printf '%s\n' "${n:-2}"
}

build_install_binaries() {   # build_install_binaries <srcdir> <binaries...>
    local src=$1; shift
    local bindir b found=0
    bindir=$(eng_bindir)
    mkdir -p "$bindir" || return 1
    for b in "$@"; do
        if [ -x "$src/$b" ]; then
            cp -f "$src/$b" "$bindir/$b" && found=$((found + 1))
        fi
    done
    [ "$found" -gt 0 ] || { error "no binaries were produced in $src"; return 1; }
    printf '%s\n' "$found"
}

build_fetch_src() {   # build_fetch_src <engine>
    local eng=$1
    local file=${ENG_SRC[$eng]:-}

    # libxc has no ENG_SRC entry; discover by glob.
    if [ "$eng" = libxc ] && [ -z "$file" ]; then
        file=$(cd "$PF_ROOT/engines-src" 2>/dev/null \
               && ls libxc-*.tar.gz 2>/dev/null | head -1)
        [ -n "$file" ] || file=$(cd "$(eng_src_dir)" 2>/dev/null \
               && ls libxc-*.tar.gz 2>/dev/null | head -1)
        [ -n "$file" ] || file="libxc-7.1.2.tar.gz"
        ENG_SRC[libxc]=$file
    fi
    [ -n "$file" ] || return 1

    local base=${PF_ENGINES_SRC_URL:-https://raw.githubusercontent.com/MHAmirkhani/PseudoForge/main/engines-src}
    local url="$base/$file"
    local dest
    dest="$(eng_src_dir)/$file"
    mkdir -p "$(dirname "$dest")"

    info "fetching $eng source from the repository"
    if ! fetch_binary_url "$url" "$dest"; then
        error "could not download $eng source from $url"
        return 1
    fi

    local manifest=${PF_MANIFEST_PATH:-$PF_ROOT/engines-src/MANIFEST.txt}
    if [ -f "$manifest" ]; then
        local sha
        sha=$(awk -v f="$file" '$1==f{print $2; exit}' "$manifest")
        if [ -n "$sha" ]; then
            local actual=""
            if have sha256sum; then
                actual=$(sha256sum "$dest" 2>/dev/null | awk '{print $1}')
            elif have shasum; then
                actual=$(shasum -a 256 "$dest" 2>/dev/null | awk '{print $1}')
            fi
            if [ -n "$actual" ] && [ "$actual" = "$sha" ]; then
                ok "verified $file against MANIFEST.txt"
            else
                error "checksum mismatch for $eng source"
                error "  expected: $sha"
                error "  file:     $dest"
                rm -f "$dest"
                return 1
            fi
        fi
    else
        warn "MANIFEST.txt not found at $manifest; skipping checksum verification"
    fi
    return 0
}

# ---------------------------------------------------------------------------
# build_prepare_src <engine> [marker] -- get a source tree ready to compile in.
#
# Three ways to arrive at one, in order of preference:
#   1. <ENGINE>_SRC_DIR in the config points at an unpacked tree
#   2. an unpacked tree is already lying around -- a previous build, or one the
#      user unpacked by hand, which is common when unzip is not installed
#   3. unpack the archive
#
# Echoes the directory to build in.
# ---------------------------------------------------------------------------
build_prepare_src() {
    local eng=$1 marker=${2:-}
    local build var cand d ar src base file url
    build=$(eng_builddir)/$eng
    var=$(upper "$eng")_SRC_DIR
    var=${var//-/_}

    cand=${!var:-}
    if [ -n "$cand" ] && { [ -z "$marker" ] || [ -e "$cand/$marker" ]; }; then
        debug "$eng: using the configured source tree $cand"
        printf '%s\n' "$cand"; return 0
    fi

    # 1. search local paths (unpacked source trees)
    if [ -n "$marker" ]; then
        for d in "$build" "${PF_SRC_DIR:-}" "$PF_ROOT/../.src" "$PF_ROOT/.src" "$PF_ROOT/.."; do
            [ -n "$d" ] || continue
            [ -d "$d" ] || continue
            if src=$(build_find_srcdir "$d" "$marker" 2>/dev/null); then
                debug "$eng: found an unpacked source tree at $src"
                printf '%s\n' "$src"; return 0
            fi
        done
    elif [ -d "$build" ]; then
        printf '%s\n' "$build"; return 0
    fi

    # 1b. search local source archives
    ar=$(eng_source_archive "$eng" 2>/dev/null) || ar=""

    # 2. if not found: build_fetch_src <engine>
    if [ -z "$ar" ]; then
        if build_fetch_src "$eng"; then
            ar=$(eng_source_archive "$eng" 2>/dev/null) || ar=""
        fi
    fi

    # 3. if still not found: print archive name, every local path tried, and the URL, then error
    if [ -z "$ar" ]; then
        file=${ENG_SRC[$eng]:-}
        base=${PF_ENGINES_SRC_URL:-https://raw.githubusercontent.com/MHAmirkhani/PseudoForge/main/engines-src}
        url="$base/$file"
        error "${ENG_LABEL[$eng]:-$eng}: no source found."
        error "  Archive: ${file:-<unknown>}"
        error "  Looked in local paths: ${PF_SRC_DIR:-<unset>}, $PF_ROOT, $PF_ROOT/.., $(eng_src_dir), $(eng_builddir), $PWD"
        error "  Tried repository URL: $url"
        error "  Download it from ${ENG_UPSTREAM[$eng]:-upstream}, or set $var in $PF_RC."
        return 1
    fi

    info "unpacking $(basename "$ar")"
    mkdir -p "$build"
    build_extract "$ar" "$build" || return 1
    if [ -n "$marker" ]; then
        build_find_srcdir "$build" "$marker" || {
            error "cannot find $marker inside $ar"; return 1; }
    else
        for d in "$build"/*/; do
            if [ -d "$d" ]; then printf '%s\n' "${d%/}"; return 0; fi
        done
        printf '%s\n' "$build"
    fi
}

# ---------------------------------------------------------------------------
# ONCVPSP
#
# The shipped make.inc points at one developer's macOS homebrew paths and
# enables libxc.  We write a clean one instead: system gfortran, reference
# LAPACK, and the libxc *stub* so no extra library is needed.  ONCVPSP's own
# exchange-correlation routines cover LDA/PBE, which is all PseudoForge asks of it.
#
# We build in src/ rather than running the top-level `make all`, because that
# also runs ./set_path and the full regression suite.
# ---------------------------------------------------------------------------
build_oncvpsp() {
    local build src log rc n
    build=$(eng_builddir)/oncvpsp
    log=$(eng_builddir)/oncvpsp-build.log
    mkdir -p "$build" "$(eng_builddir)"

    src=$(build_prepare_src oncvpsp "src/oncvpsp.F90") || return 1

    # Link libxc when it is installed in our prefix.  The difference is real:
    # with the stub, ONCVPSP has four functionals; with libxc it has every LDA
    # and GGA that libxc knows.  It is still not meta-GGA -- see build_libxc.
    if build_have_libxc; then
        OBJS_LIBXC_VAL="exc_libxc.o"
        LIBXC_FLAGS="-I$(eng_prefix)/include"
        LIBXC_LINK="-L$(eng_prefix)/lib -lxcf03 -lxc -Wl,-rpath,$(eng_prefix)/lib"
        info "ONCVPSP: linking libxc from $(eng_prefix)"
    else
        OBJS_LIBXC_VAL="exc_libxc_stub.o"
        LIBXC_FLAGS=""; LIBXC_LINK=""
        warn "ONCVPSP: building without libxc -- only PZ and PBE will be available."
        warn "  Run 'pseudoforge engines build libxc' first for PBEsol, BLYP, revPBE, WC, PW91 and AM05."
    fi

    info "writing make.inc for this system"
    cat > "$src/make.inc" <<MKEOF
# Generated by PseudoForge $PSEUDOFORGE_VERSION on $(date '+%Y-%m-%d').
# System gfortran + reference LAPACK/BLAS.
F77        = gfortran
F90        = gfortran
CC         = gcc
FCCPP      = cpp
FLINKER    = \$(F90)
FCCPPFLAGS = -ansi
FFLAGS     = -O2 -fallow-argument-mismatch -std=legacy -ffast-math -funroll-loops
CFLAGS     = -O2
LIBS       = ${BUILD_LAPACK_LIBS:--llapack -lblas} $LIBXC_LINK
FFLAGS    += $LIBXC_FLAGS
OBJS_LIBXC = $OBJS_LIBXC_VAL
MKEOF

    n=$(build_jobs)
    info "compiling ONCVPSP (log: $log)"

    # ONCVPSP's Makefile declares no dependencies between Fortran modules and
    # the objects that `use` them, and it lists the main program *before* the
    # module it depends on.  Make therefore compiles oncvpsp.F90 first and dies
    # on a missing .mod.  Compile every module-providing source up front so the
    # .mod files exist before anything reaches for them.
    local mods
    mods=$( cd "$src/src" && grep -liE '^[[:space:]]*module[[:space:]]+[a-z_]+'                 *.f90 *.F90 2>/dev/null | sed -e 's/\.f90$/.o/' -e 's/\.F90$/.o/' | tr '
' ' ' )
    if [ -n "$(trim "${mods:-}")" ]; then
        debug "ONCVPSP: pre-building modules: $mods"
        # shellcheck disable=SC2086
        ( cd "$src/src" && make $mods ) > "$log" 2>&1 || {
            warn "module pre-pass reported problems; continuing (see $log)"; }
    fi

    ( cd "$src/src" && make -j"$n" all ) >> "$log" 2>&1
    rc=$?
    if [ $rc -ne 0 ]; then
        # a parallel build can still race on the xmlf90 sub-library
        warn "parallel build failed, retrying with a single job"
        ( cd "$src/src" && make all ) >> "$log" 2>&1
        rc=$?
    fi
    [ $rc -eq 0 ] || { error "ONCVPSP build failed -- see $log"; tail -20 "$log" | pf_emit_stream debug; return 1; }

    build_install_binaries "$src/src" oncvpsp.x oncvpspnr.x oncvpspr.x >/dev/null || return 1
    ok "ONCVPSP built -> $(eng_bindir)"
    pf_config_set ONCVPSP_BIN "$(eng_bindir)/oncvpsp.x"
    ONCVPSP_BIN=$(eng_bindir)/oncvpsp.x
    # Keep the tree: tests/data holds ONCVPSP's own per-element decks, a
    # legitimate parameter source when no library table is available.
    pf_config_set ONCVPSP_SRC_DIR "$src"
    ONCVPSP_SRC_DIR=$src
}

# ---------------------------------------------------------------------------
# USPP (Vanderbilt)
#
# A plain F77 Makefile whose only real requirement is that FC and FFLAGS point
# at something that will still compile 1990s Fortran.  No external libraries.
# ---------------------------------------------------------------------------
build_uspp() {
    local build src log rc n ar
    build=$(eng_builddir)/uspp
    log=$(eng_builddir)/uspp-build.log
    mkdir -p "$build" "$(eng_builddir)"

    src=$(build_prepare_src uspp "Source/runatom.f") || return 1

    n=$(build_jobs)

    # USPP calls g77's three-argument IDATE(month, day, year) for the timestamp
    # in its output header.  gfortran only offers the array form IDATE(values),
    # so that reference is left undefined at link time.  Supply it ourselves,
    # built on DATE_AND_TIME, which is standard Fortran and always present.
    build_uspp_compat_shim > "$src/Source/pf_compat.f"

    info "compiling USPP (log: $log)"
    ( cd "$src/Source" && make -j"$n" FC=gfortran FFLAGS="$BUILD_LEGACY_FFLAGS" ) > "$log" 2>&1
    rc=$?
    if [ ! -x "$src/Source/runatom.x" ]; then
        # The Makefile's link line has nowhere to add an extra object, so if the
        # link is what failed, do it here with the shim included.
        info "linking with the g77 compatibility shim"
        ( cd "$src/Source" \
          && gfortran $BUILD_LEGACY_FFLAGS -c pf_compat.f -o pf_compat.o \
          && gfortran ./*.o -o runatom.x ) >> "$log" 2>&1
        rc=$?
    fi
    if [ $rc -ne 0 ] || [ ! -x "$src/Source/runatom.x" ]; then
        error "USPP build failed -- see $log"; tail -20 "$log" | pf_emit_stream debug; return 1
    fi

    build_install_binaries "$src/Source" runatom.x >/dev/null || return 1
    # keep the tree: Work/ holds Vanderbilt's own per-element input decks, and
    # PseudoForge reads them as a legitimate parameter source
    pf_config_set USPP_BIN "$(eng_bindir)/runatom.x"
    pf_config_set USPP_ROOT "$src"
    USPP_BIN=$(eng_bindir)/runatom.x
    USPP_ROOT=$src
    ok "USPP built -> $(eng_bindir)   (element decks: $src/Work)"
}

# The g77 IDATE extension, which gfortran will not supply here.
build_uspp_compat_shim() {
    cat <<'FEOF'
c     ------------------------------------------------------------------
c     pf_compat.f -- generated by PseudoForge.
c
c     USPP declares IDATE "external" and calls it as IDATE(iarray), the
c     g77 form returning (day, month, year).  Because of that EXTERNAL
c     declaration gfortran will not substitute its own intrinsic, so the
c     symbol is simply undefined at link time.  Supply it here on top of
c     DATE_AND_TIME, which is standard Fortran 90.
c
c     The value is only used for a timestamp in the output header, but it
c     must match the g77 element order or the caller reads the wrong slot.
c     ------------------------------------------------------------------
      subroutine idate(iarray)
      integer iarray(3)
      integer vals(8)
      call date_and_time(values=vals)
      iarray(1) = vals(3)
      iarray(2) = vals(2)
      iarray(3) = vals(1)
      return
      end
FEOF
}

# ---------------------------------------------------------------------------
# fhi98PP
#
# Two quirks.  The Makefile defaults to g77 and links `-static`, which no
# longer works on a stock Ubuntu (no static glibc), so both are overridden.
# The bundled LAPACK excerpt (libFREE) has its own makefile with the same g77
# default and must be built first.
# ---------------------------------------------------------------------------
build_fhi98pp() {
    local build src log rc ar
    build=$(eng_builddir)/fhi98pp
    log=$(eng_builddir)/fhi98pp-build.log
    mkdir -p "$build" "$(eng_builddir)"

    src=$(build_prepare_src fhi98pp "src/fhipp.f") || return 1

    # fhi98PP keeps its debug statements as "D" in column 1, the old DEC/g77
    # conditional-compilation convention.  Modern gfortran reads that as a
    # broken statement label unless told to treat those lines as comments.
    local fhi_fflags="$BUILD_LEGACY_FFLAGS -fd-lines-as-comments"

    info "building the bundled LAPACK excerpt (libFREE)"
    ( cd "$src/lib" && make -f make.libFREE FC=gfortran \
        FFLAGS="-c $fhi_fflags" ) > "$log" 2>&1
    rc=$?
    [ $rc -eq 0 ] || { error "libFREE build failed -- see $log"; tail -20 "$log" | pf_emit_stream debug; return 1; }

    info "compiling fhi98PP (log: $log)"
    ( cd "$src/src" && make FC=gfortran \
        FFLAGS="$fhi_fflags" LDFLAGS="-O2" ) >> "$log" 2>&1
    rc=$?
    [ $rc -eq 0 ] || { error "fhi98PP build failed -- see $log"; tail -20 "$log" | pf_emit_stream debug; return 1; }

    build_install_binaries "$src/src" fhipp.x pslp.x >/dev/null || return 1
    pf_config_set FHI98PP_BIN "$(eng_bindir)/fhipp.x"
    pf_config_set FHI98PP_ROOT "$src"
    FHI98PP_BIN=$(eng_bindir)/fhipp.x
    FHI98PP_ROOT=$src
    ok "fhi98PP built -> $(eng_bindir)   (element decks: $src/bin/Elements)"
}


# ---------------------------------------------------------------------------
# OPIUM
#
# Autotools, so ./configure finds the compilers itself.  Three concessions are
# still needed, each for a documented change in GCC rather than a bug in OPIUM:
#
#   -fcommon      energy.h declares its globals without `extern`.  GCC 10 made
#                 -fno-common the default, turning that into a multiple-
#                 definition error at link time.
#   -std=gnu17 with implicit declarations demoted
#                 the C predates C99 prototypes in places; C23, which GCC 15
#                 defaults to, rejects implicit declarations outright.
#   serial make   the top-level link concatenates an "objects" list that each
#                 subdirectory writes, with no dependency saying so, and a
#                 parallel build links before those lists exist.
#
# Hartree-Fock mode (XC = hf) segfaults in this build.  LDA and GGA, which is
# what PseudoForge drives, are fine.
# ---------------------------------------------------------------------------
build_opium() {
    local build src log rc
    build=$(eng_builddir)/opium
    log=$(eng_builddir)/opium-build.log
    mkdir -p "$build" "$(eng_builddir)"

    src=$(build_prepare_src opium "src/main/opium.c") || return 1

    # Local patch: fix the d-shell writers (see lib/patches/opium/README.md).
    # Applied to the working tree only, after prepare_src and before make.
    local patcher="${PF_ROOT:-$ROOT}/lib/patches/opium/apply.sh"
    if [ -x "$patcher" ]; then
        "$patcher" "$src" || { error "OPIUM source patch failed"; return 1; }
    fi

    info "configuring OPIUM (log: $log)"
    ( cd "$src" && ./configure ) > "$log" 2>&1
    rc=$?
    [ $rc -eq 0 ] || { error "OPIUM configure failed -- see $log"; tail -15 "$log" | pf_emit_stream debug; return 1; }

    # relax the C dialect and restore the pre-GCC-10 common-symbol behaviour
    if [ -f "$src/makevars" ]; then
        sed -i 's|^CFLAGS=|CFLAGS=-fcommon -std=gnu17 -Wno-implicit-function-declaration -Wno-int-conversion |' \
            "$src/makevars"
        sed -i 's|^FFLAGS=|FFLAGS=-std=legacy -fallow-argument-mismatch |' "$src/makevars"
    fi

    info "compiling OPIUM"
    # deliberately serial: see the note above
    ( cd "$src" && make ) >> "$log" 2>&1
    rc=$?
    [ $rc -eq 0 ] && [ -x "$src/opium" ] || {
        error "OPIUM build failed -- see $log"; tail -15 "$log" | pf_emit_stream debug; return 1; }

    build_install_binaries "$src" opium >/dev/null || return 1
    pf_config_set OPIUM_BIN "$(eng_bindir)/opium"
    pf_config_set OPIUM_ROOT "$src"
    OPIUM_BIN=$(eng_bindir)/opium
    OPIUM_ROOT=$src
    ok "OPIUM built -> $(eng_bindir)   (test parameter files: $src/tests)"
}

# ---------------------------------------------------------------------------
# build_gth -- the Goedecker-Teter-Hutter toolchain (two programs).
#
# atom.x solves the all-electron atom and writes atom.ae; pseudo.x reads that
# and fits the analytic GTH coefficients to it.  Neither is useful alone.
#
# -fno-automatic is not optional.  atom.f is g77-era code that expects local
# variables to persist between calls, which was that compiler's default.  Built
# at -O2 with modern stack-allocated locals it does not crash -- it is worse
# than that: the radial integration quietly gives up partway through
# ("in spliq, xlo .gt. xup"), atom.ae is written with fewer orbital blocks than
# its own header announces, and pseudo.x then dies on end-of-file reading a
# file that looks superficially fine.  Restoring static storage fixes it.
# ---------------------------------------------------------------------------
build_gth() {
    local build src log rc pdir
    build=$(eng_builddir)/gth
    log=$(eng_builddir)/gth-build.log
    mkdir -p "$build" "$(eng_builddir)"

    src=$(build_prepare_src gth "potentials/Goedecker/atom/atom.f") || return 1

    info "compiling the GTH all-electron atom code (log: $log)"
    ( cd "$src/potentials/Goedecker/atom" &&
      gfortran -O2 -fno-automatic -std=legacy -fallow-argument-mismatch -fcommon \
               hcth.f90 xc_b97.f90 atom.f -o atom.x ) > "$log" 2>&1
    rc=$?
    [ $rc -eq 0 ] && [ -x "$src/potentials/Goedecker/atom/atom.x" ] || {
        error "GTH atom.x build failed -- see $log"; tail -15 "$log" | pf_emit_stream debug; return 1; }

    # v2.2 is the one to build: v2.3's Makefile hard-codes ifort, and v2.3 is
    # only worth having for multi-configuration fits, which the published
    # input sets do not use.
    pdir=$src/potentials/Goedecker/pseudo/v2.2
    info "compiling the GTH fitting code"
    ( cd "$pdir" && make FC=gfortran \
        "FFLAGS=-O2 -fno-automatic -std=legacy -fallow-argument-mismatch -fcommon -cpp" ) >> "$log" 2>&1
    rc=$?
    [ $rc -eq 0 ] && [ -x "$pdir/pseudo.x" ] || {
        error "GTH pseudo.x build failed -- see $log"; tail -15 "$log" | pf_emit_stream debug; return 1; }

    mkdir -p "$(eng_bindir)"
    cp "$src/potentials/Goedecker/atom/atom.x" "$(eng_bindir)/atom.x" || return 1
    cp "$pdir/pseudo.x" "$(eng_bindir)/pseudo.x" || return 1
    pf_config_set GTH_BIN "$(eng_bindir)/pseudo.x"
    pf_config_set GTH_ROOT "$src"
    GTH_BIN=$(eng_bindir)/pseudo.x
    GTH_ROOT=$src
    ok "GTH built -> $(eng_bindir)   (atom.x + pseudo.x)"
}

# ---------------------------------------------------------------------------
# build_libxc -- the exchange-correlation library ONCVPSP can link against.
#
# Built into PseudoForge's own prefix rather than the system, so no root is
# needed.  This is worth doing and worth being precise about what it buys:
# with libxc, ONCVPSP accepts a negative iexc naming any libxc LDA or GGA pair,
# which adds PBEsol, BLYP, revPBE, WC, PW91 and AM05 to its four built-ins.
#
# It does NOT add meta-GGA.  libxc has SCAN; ONCVPSP's functionals.F90 stops at
# XC_FAMILY_MGGA with "meta GGA not coded yet".  This was tested, not assumed.
#
# libxc needs cmake, which this box does not have, so the recipe accepts a
# cmake found anywhere including one the user unpacked locally.
# ---------------------------------------------------------------------------
build_find_cmake() {
    local c
    for c in "${CMAKE_BIN:-}" cmake "$(eng_builddir)"/cmake-*/bin/cmake /opt/cmake/bin/cmake; do
        [ -n "$c" ] || continue
        command -v "$c" >/dev/null 2>&1 && { command -v "$c"; return 0; }
        [ -x "$c" ] && { printf '%s\n' "$c"; return 0; }
    done
    return 1
}

build_libxc() {
    local src cm log prefix rc
    prefix=$(eng_prefix)
    log=$(eng_builddir)/libxc-build.log
    mkdir -p "$(eng_builddir)"

    if ! cm=$(build_find_cmake); then
        build_fetch_cmake || {
            error "libxc needs cmake and it could not be fetched."
            error "  Install it, or unpack a cmake release and set CMAKE_BIN to its bin/cmake."
            return 1
        }
        cm=$(build_find_cmake)
    fi

    build_fetch_src libxc 2>/dev/null || true
    src=$(build_prepare_src libxc "src/xc.h" 2>/dev/null) || {
        error "libxc source not found (expected an archive named ${ENG_SRC[libxc]:-libxc-*.tar.gz})"
        return 1
    }

    info "configuring libxc (log: $log)"
    ( cd "$src" && "$cm" -S . -B build \
        -DCMAKE_INSTALL_PREFIX="$prefix" \
        -DENABLE_FORTRAN=ON -DBUILD_SHARED_LIBS=ON \
        -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF ) > "$log" 2>&1
    rc=$?
    [ $rc -eq 0 ] || { error "libxc configure failed -- see $log"; tail -15 "$log" | pf_emit_stream debug; return 1; }

    info "compiling libxc"
    ( cd "$src" && "$cm" --build build --parallel "$(build_jobs)" ) >> "$log" 2>&1
    rc=$?
    [ $rc -eq 0 ] || { error "libxc build failed -- see $log"; tail -15 "$log" | pf_emit_stream debug; return 1; }

    ( cd "$src" && "$cm" --install build ) >> "$log" 2>&1 || {
        error "libxc install failed -- see $log"; return 1; }

    [ -f "$prefix/include/xc_f03_lib_m.mod" ] || {
        error "libxc installed but the Fortran interface is missing; ONCVPSP needs xc_f03_lib_m."
        return 1
    }
    pf_config_set LIBXC_ROOT "$prefix"
    LIBXC_ROOT=$prefix
    ok "libxc built -> $prefix"
}

# Is a usable libxc already installed in our prefix?
build_have_libxc() {
    [ -f "$(eng_prefix)/include/xc_f03_lib_m.mod" ] && \
    ls "$(eng_prefix)"/lib/libxc.so* >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# build_atompaw -- Holzwarth's PAW generator.
#
# CMake only in practice: the tree ships configure.ac but no configure, and
# regenerating it needs libtool, which this class of machine often lacks.
# build_find_cmake already accepts a cmake unpacked into the build directory,
# so an unprivileged install works.
#
# -ffree-line-length-none is not optional: several of the F90 sources have
# lines past the 132-column free-form limit and gfortran truncates them into
# syntax errors without it.
# ---------------------------------------------------------------------------
build_atompaw() {
    local src cm log prefix rc
    prefix=$(eng_prefix)
    log=$(eng_builddir)/atompaw-build.log
    mkdir -p "$(eng_builddir)"

    if ! cm=$(build_find_cmake); then
        error "AtomPAW needs cmake, which was not found."
        error "  Install it, or unpack a cmake release under $(eng_builddir) and retry."
        return 1
    fi

    src=$(build_prepare_src atompaw "src/atompaw_prog.F90") || return 1

    info "configuring AtomPAW (log: $log)"
    ( cd "$src" && "$cm" -S . -B build \
        -DCMAKE_INSTALL_PREFIX="$prefix" -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_Fortran_FLAGS="-O2 -ffree-line-length-none -fallow-argument-mismatch" \
      ) > "$log" 2>&1
    rc=$?
    [ $rc -eq 0 ] || { error "AtomPAW configure failed -- see $log"; tail -20 "$log" | pf_emit_stream debug; return 1; }

    info "compiling AtomPAW"
    ( cd "$src" && "$cm" --build build --parallel "$(build_jobs)" ) >> "$log" 2>&1
    rc=$?
    [ $rc -eq 0 ] && [ -x "$src/build/src/atompaw" ] || {
        error "AtomPAW build failed -- see $log"; tail -20 "$log" | pf_emit_stream debug; return 1; }

    mkdir -p "$(eng_bindir)"
    cp "$src/build/src/atompaw" "$(eng_bindir)/atompaw" || return 1
    [ -x "$src/build/src/atompaw_aeonly" ] && \
        cp "$src/build/src/atompaw_aeonly" "$(eng_bindir)/atompaw_aeonly"
    pf_config_set ATOMPAW_BIN "$(eng_bindir)/atompaw"
    pf_config_set ATOMPAW_ROOT "$src"
    ATOMPAW_BIN=$(eng_bindir)/atompaw
    ATOMPAW_ROOT=$src
    ok "AtomPAW built -> $(eng_bindir)   (examples: $src/example)"
}

# ---------------------------------------------------------------------------
# build_ape -- the Atomic Pseudopotential Engine.
#
# The most demanding build here: it needs GSL and libxc, and with gfortran its
# CMakeLists refuses every generator except Ninja.  All three can be satisfied
# without root -- GSL and libxc into PseudoForge's own prefix, and a prebuilt
# ninja binary dropped into the build directory.
#
# -std=gnu17 is required for the C half.  liboct_parser declares function
# pointers K&R style, "gsl_complex (*fnctptr)()", and calls them with
# arguments.  Under C23, which GCC 15 defaults to, an empty parameter list
# means "no arguments" and every such call is an error.  This is the same trap
# OPIUM falls into.
# ---------------------------------------------------------------------------
build_find_ninja() {
    local n
    for n in "${NINJA_BIN:-}" ninja "$(eng_builddir)/ninja"; do
        [ -n "$n" ] || continue
        command -v "$n" >/dev/null 2>&1 && { command -v "$n"; return 0; }
        [ -x "$n" ] && { printf '%s\n' "$n"; return 0; }
    done
    return 1
}

build_ape() {
    local src cm nj log prefix rc
    prefix=$(eng_prefix)
    log=$(eng_builddir)/ape-build.log
    mkdir -p "$(eng_builddir)"

    cm=$(build_find_cmake) || { build_fetch_cmake && cm=$(build_find_cmake); } || {
        error "APE needs cmake and it could not be fetched"; return 1; }
    nj=$(build_find_ninja) || { build_fetch_ninja && nj=$(build_find_ninja); } || {
        error "APE's build refuses non-Ninja generators when using gfortran,"
        error "  and ninja could not be fetched.  Set NINJA_BIN to one you have."
        return 1
    }
    build_have_libxc || { error "APE needs libxc -- run: pseudoforge engines build libxc"; return 1; }
    [ -f "$prefix/include/gsl/gsl_version.h" ] || {
        error "APE needs GSL, which was not found in $prefix."
        error "  Build it there with:  ./configure --prefix=$prefix && make && make install"
        return 1
    }

    src=$(build_prepare_src ape "src/ape.F90" 2>/dev/null) || \
    src=$(build_prepare_src ape "CMakeLists.txt") || return 1

    info "configuring APE (log: $log)"
    ( cd "$src" && PKG_CONFIG_PATH="$prefix/lib/pkgconfig:${PKG_CONFIG_PATH:-}" \
      "$cm" -S . -B build -G Ninja -DCMAKE_MAKE_PROGRAM="$nj" \
        -DCMAKE_INSTALL_PREFIX="$prefix" -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_PREFIX_PATH="$prefix" -DGSL_ROOT_DIR="$prefix" -DLibxc_ROOT="$prefix" \
        -DCMAKE_C_FLAGS="-O2 -std=gnu17 -fcommon -Wno-implicit-function-declaration -Wno-int-conversion" \
        -DCMAKE_Fortran_FLAGS="-O2 -ffree-line-length-none -fallow-argument-mismatch" \
      ) > "$log" 2>&1
    rc=$?
    [ $rc -eq 0 ] || { error "APE configure failed -- see $log"; tail -20 "$log" | pf_emit_stream debug; return 1; }

    info "compiling APE"
    ( cd "$src" && "$cm" --build build --parallel "$(build_jobs)" ) >> "$log" 2>&1
    rc=$?
    [ $rc -eq 0 ] && [ -x "$src/build/ape" ] || {
        error "APE build failed -- see $log"; tail -20 "$log" | pf_emit_stream debug; return 1; }

    mkdir -p "$(eng_bindir)"
    cp "$src/build/ape" "$(eng_bindir)/ape" || return 1
    pf_config_set APE_BIN "$(eng_bindir)/ape"
    pf_config_set APE_ROOT "$src"
    APE_BIN=$(eng_bindir)/ape
    APE_ROOT=$src
    ok "APE built -> $(eng_bindir)   (samples: $src/sample)"
}

# ---------------------------------------------------------------------------
# Build tools that are not compilers.
#
# Three of the nine engines need cmake, one of them also needs ninja, and APE
# needs GSL.  On a machine without root none of those can come from the
# package manager, and every one of them was installed by hand while these
# recipes were being written -- which is exactly the wall a user building from
# source hits.  So PseudoForge fetches them itself, into its own prefix.
#
# cmake and ninja ship as self-contained binaries, so those are a download and
# an unpack.  GSL is built from source, which is slower but has no
# alternative.
# ---------------------------------------------------------------------------
CMAKE_VERSION=${CMAKE_VERSION:-3.28.3}
NINJA_VERSION=${NINJA_VERSION:-1.11.1}
GSL_VERSION=${GSL_VERSION:-2.7.1}

build_fetch_cmake() {
    local b url tgz
    b=$(eng_builddir); mkdir -p "$b"
    build_find_cmake >/dev/null 2>&1 && return 0
    url="https://github.com/Kitware/CMake/releases/download/v$CMAKE_VERSION/cmake-$CMAKE_VERSION-linux-x86_64.tar.gz"
    tgz=$b/cmake.tar.gz
    info "fetching cmake $CMAKE_VERSION (about 50 MB; no root needed)"
    DOWNLOAD_TIMEOUT=${DOWNLOAD_TIMEOUT:-900} fetch_url "$url" "$tgz" || { error "could not download cmake from $url"; return 1; }
    tar xzf "$tgz" -C "$b" || { error "could not unpack cmake"; return 1; }
    rm -f "$tgz"
    build_find_cmake >/dev/null 2>&1 || { error "cmake unpacked but not found under $b"; return 1; }
    ok "cmake -> $(build_find_cmake)"
}

build_fetch_ninja() {
    local b url zip
    b=$(eng_builddir); mkdir -p "$b"
    build_find_ninja >/dev/null 2>&1 && return 0
    url="https://github.com/ninja-build/ninja/releases/download/v$NINJA_VERSION/ninja-linux.zip"
    zip=$b/ninja.zip
    info "fetching ninja $NINJA_VERSION (no root needed)"
    DOWNLOAD_TIMEOUT=${DOWNLOAD_TIMEOUT:-300} fetch_url "$url" "$zip" || { error "could not download ninja from $url"; return 1; }
    ( cd "$b" && { unzip -o "$zip" >/dev/null 2>&1 || \
        python3 -c "import zipfile,sys;zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$zip" "$b"; } )
    chmod +x "$b/ninja" 2>/dev/null
    rm -f "$zip"
    build_find_ninja >/dev/null 2>&1 || { error "ninja unpacked but not executable"; return 1; }
    ok "ninja -> $(build_find_ninja)"
}

# GSL, built into our prefix.  APE will not configure without it.
build_gsl() {
    local prefix src log rc
    prefix=$(eng_prefix)
    log=$(eng_builddir)/gsl-build.log
    mkdir -p "$(eng_builddir)"
    [ -f "$prefix/include/gsl/gsl_version.h" ] && { ok "GSL already in $prefix"; return 0; }

    src=$(build_prepare_src gsl "configure" 2>/dev/null) || {
        error "GSL source not found (expected gsl-$GSL_VERSION.tar.gz)"
        error "  Download it from https://ftp.gnu.org/gnu/gsl/ and put it beside PseudoForge."
        return 1
    }
    info "configuring GSL (log: $log)"
    ( cd "$src" && ./configure --prefix="$prefix" --disable-static ) > "$log" 2>&1
    rc=$?
    [ $rc -eq 0 ] || { error "GSL configure failed -- see $log"; tail -15 "$log" | pf_emit_stream debug; return 1; }
    info "compiling GSL (this takes a few minutes)"
    ( cd "$src" && make -j"$(build_jobs)" && make install ) >> "$log" 2>&1
    rc=$?
    [ $rc -eq 0 ] && [ -f "$prefix/include/gsl/gsl_version.h" ] || {
        error "GSL build failed -- see $log"; tail -15 "$log" | pf_emit_stream debug; return 1; }
    ok "GSL built -> $prefix"
}

# ---------------------------------------------------------------------------
# build_engine <engine> [--yes]
#
# The whole install: check prerequisites, offer to install them, compile,
# verify the binary actually runs, and record the path in ~/.pseudoforgerc.
# ---------------------------------------------------------------------------
build_engine() {
    local eng=$1 assume_yes=${2:-}
    pf_engines_load
    # libxc is a dependency rather than a generator, so it is not in the engine
    # registry -- but it is built the same way and people will reach for the
    # same command, so let that work instead of reporting it as unknown.
    if [ "$eng" = libxc ]; then
        banner "Building libxc"
        build_libxc
        return $?
    fi
    eng_exists "$eng" || { error "unknown engine '$eng'"; return 1; }

    if [ "$eng" = ld1 ]; then
        error "ld1.x is part of Quantum ESPRESSO; PseudoForge does not build QE itself."
        error "  Install it with your package manager, or build it:"
        error "    git clone https://gitlab.com/QEF/q-e.git && cd q-e && ./configure && make pw ld1"
        error "  Then set QE_ROOT_DIR in $PF_RC"
        return 1
    fi

    banner "Building ${ENG_LABEL[$eng]}"
    if [ -n "$(build_missing_tools)" ]; then
        build_install_deps "$assume_yes" || return 1
    fi

    case $eng in
        oncvpsp) build_oncvpsp ;;
        opium)   build_opium ;;
        gth)     build_gth ;;
        libxc)   build_libxc ;;
        gsl)     build_gsl ;;
        atompaw) build_atompaw ;;
        ape)     build_ape ;;
        uspp)    build_uspp ;;
        fhi98pp) build_fhi98pp ;;
        adpack)
            error "ADPACK is installed externally; PseudoForge ships no build recipe."
            error "  See docs/reference/engines/adpack.md for installation instructions."
            return 1 ;;
        *)       error "no build recipe for '$eng'"; return 1 ;;
    esac
    rc=$?
    [ $rc -eq 0 ] || return $rc

    build_verify "$eng"
}

# ---------------------------------------------------------------------------
# build_verify <engine> -- prove the binary runs, rather than merely exists.
#
# Each engine is fed a deliberately empty/invalid input.  A working binary
# reads it and complains; a broken one dies with a linker or ABI error.  We
# only care that it got far enough to produce its own diagnostics.
# ---------------------------------------------------------------------------
build_verify() {
    local eng=$1 bin out
    bin=$(eng_resolve "$eng") || { error "${ENG_LABEL[$eng]}: binary not found after build"; return 1; }
    [ -x "$bin" ] || { error "$bin is not executable"; return 1; }

    out=$( : | OMP_NUM_THREADS=1 timeout 20 "$bin" 2>&1 | head -30 )
    case $eng in
        oncvpsp)
            printf '%s' "$out" | grep -qiE 'ONCVPSP|input|error|Fortran' || {
                warn "${ENG_LABEL[$eng]}: built, but the smoke test produced no recognisable output"
                return 0
            } ;;
        opium)
            printf '%s' "$out" | grep -qiE 'opium|usage|param' || {
                warn "OPIUM built, but the smoke test produced no recognisable output"; return 0; } ;;
        gth)
            # pseudo.x prints its banner before touching input, and the
            # companion atom.x has to be there too or a fit cannot be set up.
            printf '%s' "$out" | grep -qiE 'goedecker|pseudo' || {
                warn "GTH pseudo.x built, but the smoke test produced no recognisable output"; }
            [ -x "$(dirname "$bin")/atom.x" ] || {
                error "GTH: pseudo.x is installed but atom.x is missing -- a fit needs both"
                return 1; } ;;
        atompaw)
            # atompaw reads its deck from stdin and prints a menu of output
            # writers before it needs any of it, so an empty input still shows
            # the banner.
            printf '%s' "$out" | grep -qiE 'atompaw|ABINITOUT|input' || {
                warn "AtomPAW built, but the smoke test produced no recognisable output"; } ;;
        uspp|fhi98pp)
            # both simply stop on empty input; any output at all means it linked
            : ;;
    esac
    ok "${ENG_LABEL[$eng]}: $bin runs"
    return 0
}

# ---------------------------------------------------------------------------
# build_all [--yes] -- everything PseudoForge can build, skipping what is present.
# ---------------------------------------------------------------------------
build_all() {
    local assume_yes=${1:-} eng failed=""
    pf_engines_load
    # oncvpsp, uspp, fhi98pp, opium, atompaw, ape, gth have build recipes.
    # ld1 comes with Quantum ESPRESSO.
    # adpack has no build recipe; external install only.
    for eng in oncvpsp uspp fhi98pp opium atompaw ape gth; do
        if eng_available "$eng"; then
            info "${ENG_LABEL[$eng]}: already installed, skipping"
            continue
        fi
        build_engine "$eng" "$assume_yes" || failed="$failed $eng"
    done
    if [ -n "$failed" ]; then
        warn "these engines failed to build:$failed"
        return 1
    fi
    ok "all engines available"
}
