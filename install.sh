#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# install.sh -- put pseudoforge on your PATH, install dependencies, or bootstrap.
#
#   ./install.sh                 symlink into ~/.local/bin and run doctor
#   ./install.sh [DEST_DIR]      symlink somewhere else
#   ./install.sh --deps          install system packages for this OS
#   ./install.sh --deps --yes    install system packages without confirmation
#   ./install.sh --bootstrap     --deps then engines build all
#   ./install.sh --dry-run ...   print commands, execute nothing, touch no files
# ---------------------------------------------------------------------------
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=lib/core.sh
. "$ROOT/lib/core.sh"
# shellcheck source=lib/deps.sh
. "$ROOT/lib/deps.sh"

show_help() {
    cat << 'EOF'
Usage: ./install.sh [OPTIONS] [DEST_DIR]

Options:
  --deps         Install system packages for your operating system
  --bootstrap    Install dependencies and build all eight supported engines
  --dry-run      Print commands without executing them or modifying files
  --yes, -y      Skip confirmation prompts (assume yes)
  --help, -h     Show this help message

Arguments:
  DEST_DIR       Directory to symlink pseudoforge into (default: ~/.local/bin)
EOF
}

print_qe_note() {
    cat << 'EOF'

Quantum ESPRESSO is not installed by this script.
ld1.x will prompt to install it the first time a run needs it,
or you can build it now with:
    pseudoforge engines build ld1
Install guide: https://www.quantum-espresso.org/
EOF
}

do_deps=false
do_bootstrap=false
dry_run=false
assume_yes=false
dest=""

while [ $# -gt 0 ]; do
    case $1 in
        --help|-h)
            show_help
            exit 0
            ;;
        --deps)
            do_deps=true
            shift
            ;;
        --bootstrap)
            do_bootstrap=true
            do_deps=true
            shift
            ;;
        --dry-run)
            dry_run=true
            shift
            ;;
        --yes|-y)
            assume_yes=true
            shift
            ;;
        -*)
            echo "Unknown option: $1" >&2
            echo "Try './install.sh --help' for more information." >&2
            exit 2
            ;;
        *)
            if [ -z "$dest" ]; then
                dest=$1
            else
                echo "Unexpected argument: $1" >&2
                exit 2
            fi
            shift
            ;;
    esac
done

DEST=${dest:-$HOME/.local/bin}

# ---------------------------------------------------------------------------
# --deps flow
# ---------------------------------------------------------------------------
if [ "$do_deps" = true ]; then
    os=$(pf_detect_os)
    build_engines=${BUILD_ENGINES:-}

    if [ -z "$build_engines" ]; then
        if [ "$do_bootstrap" = true ] || [ "$assume_yes" = true ] || [ ! -t 0 ]; then
            build_engines=yes
        else
            printf 'Will you build engines on this machine? [y/N] '
            read -r ans
            case $ans in
                y|Y|yes|YES) build_engines=yes ;;
                *) build_engines=no ;;
            esac
        fi
    fi

    cmd=""
    case $os in
        debian)
            if [ "$build_engines" = yes ]; then
                cmd="sudo apt-get install -y gfortran gcc make libblas-dev liblapack-dev unzip curl"
            else
                cmd="sudo apt-get install -y bash coreutils gawk sed grep curl"
            fi
            ;;
        fedora|rhel)
            if [ "$build_engines" = yes ]; then
                cmd="sudo dnf install -y gcc-gfortran gcc make blas-devel lapack-devel unzip curl"
            else
                cmd="sudo dnf install -y bash coreutils gawk sed grep curl"
            fi
            ;;
        arch)
            if [ "$build_engines" = yes ]; then
                cmd="sudo pacman -S --needed --noconfirm gcc-fortran gcc make blas lapack unzip curl"
            else
                cmd="sudo pacman -S --needed --noconfirm bash coreutils gawk sed grep curl"
            fi
            ;;
        macos)
            if [ "$build_engines" = yes ]; then
                cmd="brew install gcc make openblas unzip curl"
            else
                cmd="brew install bash coreutils gawk gnu-sed grep curl"
            fi
            ;;
        *)
            if [ "$build_engines" = yes ]; then
                cmd="Please install with your package manager: gfortran, gcc, make, BLAS/LAPACK, unzip, curl"
            else
                cmd="Please install with your package manager: bash, coreutils, gawk, sed, grep, curl"
            fi
            ;;
    esac

    if [ "$dry_run" = true ]; then
        echo "$cmd"
        if [ "$do_bootstrap" = true ]; then
            echo "$ROOT/pseudoforge engines build all"
        fi
        exit 0
    fi

    all_present=true
    if [ "$build_engines" = yes ]; then
        for t in gfortran gcc make unzip curl; do
            have "$t" || { all_present=false; break; }
        done
        if [ "$all_present" = true ]; then
            # shellcheck source=lib/build.sh
            . "$ROOT/lib/build.sh" 2>/dev/null || true
            build_have_lapack || all_present=false
        fi
    else
        for t in bash awk sed grep find mkdir mktemp date curl; do
            have "$t" || { all_present=false; break; }
        done
    fi

    if [ "$all_present" = true ]; then
        echo "All dependencies are already installed."
    else
        echo "Installation command for $os:"
        echo "  $cmd"
        if [ "$assume_yes" = false ] && [ -t 0 ]; then
            printf 'Proceed? [y/N] '
            read -r proceed
            case $proceed in
                y|Y|yes|YES) ;;
                *) echo "Aborted."; exit 1 ;;
            esac
        fi

        if [[ "$cmd" =~ ^(sudo|brew) ]]; then
            eval "$cmd"
        fi
    fi

    # Verify required dependencies via doctor
    if ! "$ROOT/pseudoforge" doctor --check; then
        echo "Error: required dependencies are still missing." >&2
        exit 1
    fi

    mkdir -p "$DEST"
    ln -sf "$ROOT/pseudoforge" "$DEST/pseudoforge"
    echo "linked $DEST/pseudoforge -> $ROOT/pseudoforge"

    if [ "$do_bootstrap" = true ]; then
        echo
        echo "== Building eight supported engines =="
        "$ROOT/pseudoforge" engines build all
        echo
        echo "== Installed engines status =="
        "$ROOT/pseudoforge" doctor
    fi

    print_qe_note
    exit 0
fi

# ---------------------------------------------------------------------------
# Default flow: symlink into DEST and run doctor
# ---------------------------------------------------------------------------
if [ "$dry_run" = true ]; then
    echo "mkdir -p $DEST"
    echo "ln -sf $ROOT/pseudoforge $DEST/pseudoforge"
    echo "$ROOT/pseudoforge doctor"
    exit 0
fi

mkdir -p "$DEST"
ln -sf "$ROOT/pseudoforge" "$DEST/pseudoforge"
echo "linked $DEST/pseudoforge -> $ROOT/pseudoforge"

case ":$PATH:" in
    *":$DEST:"*) ;;
    *) echo
       echo "$DEST is not on your PATH. Add this to your shell profile:"
       echo "    export PATH=\"$DEST:\$PATH\"" ;;
esac

echo
"$ROOT/pseudoforge" doctor
