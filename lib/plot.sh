# shellcheck shell=bash
# ---------------------------------------------------------------------------
# plot.sh -- pictures of what a run produced.
#
# Four things are worth looking at, and PseudoForge produces the data for two
# of them:
#
#   logder   log derivatives, all-electron against pseudo.  The standard way
#            to see a ghost state: the two curves should lie on top of each
#            other, and a pole in one and not the other is a ghost.
#   wfc      radial wavefunctions, all-electron against pseudo.  They must
#            agree outside the matching radius and be smooth inside it.
#   bands    a band structure, from Quantum ESPRESSO's own bands.x
#   dos      a density of states, from dos.x
#
# **Bands and DOS are not something PseudoForge computes.** Generating a
# pseudopotential does not involve a crystal, and pretending otherwise would
# mean inventing a structure, a k-path and a cutoff on the user's behalf and
# labelling the result as theirs. So those two plotters read the output of the
# QE tools that do compute them, and when there is no such output `--plot`
# says which command would produce it rather than quietly drawing nothing.
#
# Rendering is done by whatever is on PATH: gnuplot if present, else
# matplotlib through python3, else nothing and a clear message. Neither is
# bundled and neither is required -- `--plot` on a machine with no backend
# prints what it would have drawn and exits 0, because a missing plotting
# program is not a failed pseudopotential.
#
# python3 here is an external renderer reached through PATH, exactly as
# gnuplot is. It is not core logic: nothing in lib/ depends on it, and with
# both backends absent every other feature behaves identically.
#
# Both backends render from one description -- a TSV whose first line is a
# `#`-comment naming the columns, x in column 1 and one series per column
# after it. One description, two renderers, so the two cannot drift into
# drawing different pictures from the same data.
# ---------------------------------------------------------------------------

PLOT_ENABLED=${PLOT_ENABLED:-0}
PLOT_FORMAT=${PLOT_FORMAT:-png}
PLOT_WIDTH=${PLOT_WIDTH:-900}
PLOT_HEIGHT=${PLOT_HEIGHT:-600}

# Log-derivative sampling, handed to ld1.x when plotting is on.  These change
# nothing about the pseudopotential: they are read by the iswitch=2 validation
# run, which happens after the UPF has been written.
PLOT_EMINLD=${PLOT_EMINLD:--3.0}
PLOT_EMAXLD=${PLOT_EMAXLD:-3.0}
PLOT_DELD=${PLOT_DELD:-0.02}
PLOT_NLD=${PLOT_NLD:-3}
PLOT_RLDERIV=${PLOT_RLDERIV:-}     # empty = derive it from the recipe

# Axis limits for the next plot_series call, as "lo:hi"; empty means autoscale.
# A log-derivative plot autoscaled to its own poles is a flat line with one
# spike, and a radial wavefunction autoscaled to the full 100-bohr grid is a
# flat line at the left edge -- in both cases the picture is technically
# correct and shows nothing.
PLOT_XRANGE=
PLOT_YRANGE=

PLOT_MADE=0
PLOT_SKIPPED=""

# ---------------------------------------------------------------------------
# plot_backend -- which renderer, if any.
#
# "python3 exists" is not the same as "matplotlib is installed", and on a
# stock Debian it usually is not, so the probe imports it.
# ---------------------------------------------------------------------------
plot_backend() {
    if [ -n "${PLOT_BACKEND_CACHED:-}" ]; then
        printf '%s\n' "$PLOT_BACKEND_CACHED"
        [ "$PLOT_BACKEND_CACHED" != none ]
        return
    fi
    local b=none
    if have gnuplot; then
        b=gnuplot
    elif have python3 && python3 -c 'import matplotlib' >/dev/null 2>&1; then
        b=matplotlib
    fi
    PLOT_BACKEND_CACHED=$b
    printf '%s\n' "$b"
    [ "$b" != none ]
}

plot_backend_label() {
    case $(plot_backend) in
        gnuplot)    printf 'gnuplot %s\n' "$(gnuplot --version 2>/dev/null | awk '{print $2}')" ;;
        matplotlib) printf 'matplotlib %s\n' \
                        "$(python3 -c 'import matplotlib;print(matplotlib.__version__)' 2>/dev/null)" ;;
        *)          printf 'none\n' ;;
    esac
}

# ---------------------------------------------------------------------------
# plot_rlderiv <project> <element>
#
# Log derivatives have to be sampled outside the matching region, or the curve
# is dominated by the pseudisation rather than by the scattering it is meant
# to show.  Take the largest rcut/rcutus in the recipe's own card block and
# stand off from it; if the deck cannot be read, fall back to a radius that is
# outside the core for most elements and say so when it is used.
# ---------------------------------------------------------------------------
plot_rlderiv() {
    local proj=$1 el=$2 deck r
    [ -n "$PLOT_RLDERIV" ] && { printf '%s\n' "$PLOT_RLDERIV"; return 0; }
    deck=$(ls "$proj"/inputs/"$el".*.in 2>/dev/null | head -1)
    if [ -n "$deck" ] && [ -f "$deck" ]; then
        # Card lines are: label n l occupation energy rcut rcutus jj
        r=$(awk 'NF == 8 && $2 ~ /^[0-9]+$/ && $3 ~ /^[0-9]+$/ {
                     if ($6 + 0 > m) m = $6 + 0
                     if ($7 + 0 > m) m = $7 + 0
                 } END { if (m > 0) printf "%.2f\n", m + 0.3 }' "$deck")
    fi
    printf '%s\n' "${r:-2.50}"
}

# ---------------------------------------------------------------------------
# plot_series <outfile> <title> <xlabel> <ylabel> <tsv>
#
# The one rendering entry point.  The TSV's first line must be a #-comment
# naming the columns.
# ---------------------------------------------------------------------------
plot_series() {
    local out=$1 title=$2 xlab=$3 ylab=$4 data=$5
    case $(plot_backend) in
        gnuplot)    plot_series_gnuplot "$@" ;;
        matplotlib) plot_series_mpl "$@" ;;
        *)          return 1 ;;
    esac
}

plot_series_gnuplot() {
    local out=$1 title=$2 xlab=$3 ylab=$4 data=$5
    local script ncol i spec names
    ncol=$(awk 'NR == 2 { print NF; exit }' "$data")
    [ "${ncol:-0}" -ge 2 ] || return 1
    names=$(head -1 "$data" | sed 's/^#[[:space:]]*//')

    script=$(mktemp)
    {
        printf 'set terminal %scairo size %s,%s font "sans,11"\n' \
               "$PLOT_FORMAT" "$PLOT_WIDTH" "$PLOT_HEIGHT"
        printf 'set output "%s"\n' "$out"
        printf 'set title "%s"\n'  "$title"
        printf 'set xlabel "%s"\n' "$xlab"
        printf 'set ylabel "%s"\n' "$ylab"
        printf 'set key outside right\n'
        printf 'set grid\n'
        [ -n "$PLOT_XRANGE" ] && echo "set xrange [$PLOT_XRANGE]"
        [ -n "$PLOT_YRANGE" ] && echo "set yrange [$PLOT_YRANGE]"
        i=2; spec=
        while [ "$i" -le "$ncol" ]; do
            [ -n "$spec" ] && spec="$spec, "
            spec="$spec'$data' using 1:$i with lines lw 2 title '$(printf '%s' "$names" | awk -v n=$((i - 1)) '{print $n}')'"
            i=$((i + 1))
        done
        printf 'plot %s\n' "$spec"
    } > "$script"
    gnuplot "$script" >/dev/null 2>&1
    local rc=$?
    rm -f "$script"
    [ "$rc" = 0 ] && [ -s "$out" ]
}

plot_series_mpl() {
    local out=$1 title=$2 xlab=$3 ylab=$4 data=$5
    local script rc
    script=$(mktemp --suffix=.py)
    # Written to a file rather than passed with -c: the plot titles contain
    # quotes and brackets, and a shell-quoted one-liner is where that breaks.
    {
        printf 'import matplotlib\n'
        printf 'matplotlib.use("Agg")\n'
        printf 'import matplotlib.pyplot as plt\n'
        printf 'import sys, io\n'
        printf 'data, title, xlab, ylab, out = sys.argv[1:6]\n'
        printf 'names, rows = [], []\n'
        printf 'for line in io.open(data, encoding="utf-8"):\n'
        printf '    line = line.rstrip("\\n")\n'
        printf '    if line.startswith("#"):\n'
        printf '        if not names: names = line.lstrip("#").split()\n'
        printf '        continue\n'
        printf '    if not line.strip(): continue\n'
        printf '    try: rows.append([float(v) for v in line.split()])\n'
        printf '    except ValueError: continue\n'
        printf 'if not rows: sys.exit(3)\n'
        printf 'ncol = min(len(r) for r in rows)\n'
        printf 'x = [r[0] for r in rows]\n'
        printf 'fig, ax = plt.subplots(figsize=(%s/100.0, %s/100.0), dpi=100)\n' \
               "$PLOT_WIDTH" "$PLOT_HEIGHT"
        printf 'for c in range(1, ncol):\n'
        printf '    label = names[c] if c < len(names) else "col%%d" %% (c + 1)\n'
        printf '    ax.plot(x, [r[c] for r in rows], lw=1.6, label=label)\n'
        printf 'ax.set_title(title); ax.set_xlabel(xlab); ax.set_ylabel(ylab)\n'
        [ -n "$PLOT_XRANGE" ] && echo "ax.set_xlim(${PLOT_XRANGE%%:*}, ${PLOT_XRANGE##*:})"
        [ -n "$PLOT_YRANGE" ] && echo "ax.set_ylim(${PLOT_YRANGE%%:*}, ${PLOT_YRANGE##*:})"
        printf 'ax.grid(alpha=0.3)\n'
        printf 'ax.legend(loc="center left", bbox_to_anchor=(1.01, 0.5), frameon=False)\n'
        printf 'fig.tight_layout()\n'
        printf 'fig.savefig(out)\n'
    } > "$script"
    python3 "$script" "$data" "$title" "$xlab" "$ylab" "$out" >/dev/null 2>&1
    rc=$?
    rm -f "$script"
    [ "$rc" = 0 ] && [ -s "$out" ]
}

# ---------------------------------------------------------------------------
# The four plots.  Each finds its data, writes the common TSV, renders it, and
# records what it did -- or what it could not do, and why.
# ---------------------------------------------------------------------------
plot_note_skip() { PLOT_SKIPPED="${PLOT_SKIPPED}$1"$'\n'; }

# Log derivatives: ld1N.dlog is all-electron, ld1Nps.dlog the pseudo, one
# column per angular momentum after the energy.
plot_logder() {
    local proj=$1 el=$2 dir=$3 ae ps out tsv n
    ae=$proj/tests/ld11.dlog
    ps=$proj/tests/ld11ps.dlog
    if [ ! -f "$ae" ] || [ ! -f "$ps" ]; then
        plot_note_skip "$el logder: no log-derivative data (generate with --plot)"
        return 1
    fi
    n=$(awk 'NR == 1 { print NF - 1; exit }' "$ae")
    tsv=$(mktemp)
    {
        printf '# energy(Ry)'
        local l=0
        while [ "$l" -lt "${n:-0}" ]; do
            printf ' AE-l=%s' "$l"; l=$((l + 1))
        done
        l=0
        while [ "$l" -lt "${n:-0}" ]; do
            printf ' PS-l=%s' "$l"; l=$((l + 1))
        done
        printf '\n'
        # Same energy grid in both files, so paste them and drop the repeated
        # first column.
        paste "$ae" "$ps" | awk -v n="$n" '{
            printf "%s", $1
            for (i = 2; i <= n + 1; i++)           printf " %s", $i
            for (i = n + 3; i <= 2 * n + 2; i++)   printf " %s", $i
            printf "\n" }'
    } > "$tsv"
    # Every channel has a pole where it crosses a bound state, and one pole
    # 500 units tall flattens every other curve in the picture.  Clip to the
    # bulk of the data: the poles still read as spikes leaving the frame,
    # which is how these plots are normally shown, and the AE/PS agreement
    # the plot exists to show becomes visible.
    local yb
    yb=$(awk 'NR > 1 { for (i = 2; i <= NF; i++) { v = $i + 0; if (v < 0) v = -v; print v } }' "$tsv" | sort -g | awk '{ a[NR] = $1 } END { if (NR) printf "%.2f", a[int(NR * 0.90)] * 2.5 }')
    case $yb in ""|0.00|0) yb=10 ;; esac
    PLOT_YRANGE="-$yb:$yb"

    out=$dir/$el.logder.$PLOT_FORMAT
    if plot_series "$out" "$el -- log derivatives at r = $(plot_rlderiv "$proj" "$el") bohr" \
                   "energy (Ry)" "d ln psi / dr" "$tsv"; then
        PLOT_YRANGE=; rm -f "$tsv"; PLOT_MADE=$((PLOT_MADE + 1)); printf '%s\n' "$out"; return 0
    fi
    PLOT_YRANGE=; rm -f "$tsv"
    plot_note_skip "$el logder: the renderer produced nothing"
    return 1
}

# Radial wavefunctions: ld1N.wfc already carries a #-comment header naming the
# orbitals, which is the format plot_series wants, so it is plotted directly.
plot_wfc() {
    local proj=$1 el=$2 dir=$3 ae ps out tsv xmax
    ae=$proj/tests/ld11.wfc
    ps=$proj/tests/ld11ps.wfc
    if [ ! -f "$ae" ]; then
        plot_note_skip "$el wfc: no wavefunction data in $proj/tests"
        return 1
    fi
    tsv=$(mktemp)
    if [ -f "$ps" ]; then
        # The two files do not have the same number of orbitals -- the pseudo
        # atom has fewer, which is the point of it -- so each header is read on
        # its own terms.  Folding them as though the counts matched put the
        # pseudo file's "r" column in as a data series and shifted every label
        # after it onto the wrong curve.
        awk '
          FILENAME == aef && /^#/ && !aeh { for (i = 3; i <= NF; i++) an[++na] = $i; aeh = 1; next }
          FILENAME == psf && /^#/ && !psh { for (i = 3; i <= NF; i++) pn[++np] = $i; psh = 1; next }
          FILENAME == aef && !/^#/ { ar[++arn] = $0; next }
          FILENAME == psf && !/^#/ { pr[++prn] = $0; next }
          END {
              printf "# r"
              for (i = 1; i <= na; i++) printf " AE:%s", an[i]
              for (i = 1; i <= np; i++) printf " PS:%s", pn[i]
              printf "\n"
              n = (arn < prn ? arn : prn)
              for (k = 1; k <= n; k++) {
                  split(ar[k], a, " "); split(pr[k], p, " ")
                  printf "%s", a[1]
                  for (i = 2; i <= na + 1; i++) printf " %s", a[i]
                  for (i = 2; i <= np + 1; i++) printf " %s", p[i]
                  printf "\n"
              }
          }' aef="$ae" psf="$ps" "$ae" "$ps" > "$tsv"
    else
        cp "$ae" "$tsv"
    fi

    # The radial grid runs to about 100 bohr and every orbital is flat after a
    # few.  Cut where the last curve stops being distinguishable from zero, so
    # the plot shows the part that carries the information.
    xmax=$(awk 'NR > 1 { for (i = 2; i <= NF; i++) { v = $i + 0; if (v < 0) v = -v
                     if (v > 1e-3) { r = $1 + 0; break } }
                     if (r > m) m = r }
                END { printf "%.1f\n", (m > 0 ? m * 1.15 : 12) }' "$tsv")
    PLOT_XRANGE="0:${xmax:-12}"
    out=$dir/$el.wfc.$PLOT_FORMAT
    if plot_series "$out" "$el -- radial wavefunctions (AE vs PS)" \
                   "r (bohr)" "r psi(r)" "$tsv"; then
        PLOT_XRANGE=; rm -f "$tsv"
        PLOT_MADE=$((PLOT_MADE + 1)); printf '%s\n' "$out"; return 0
    fi
    PLOT_XRANGE=; rm -f "$tsv"
    plot_note_skip "$el wfc: the renderer produced nothing"
    return 1
}

# Band structure, from bands.x output.  Not something this project computes;
# it plots one if the user has produced one.
plot_bands() {
    local proj=$1 dir=$2 src out
    # A file the user named and that is not there is a different problem from
    # having no data at all, and saying "PseudoForge does not compute one" to
    # someone who just pointed at their own output is no help.
    if [ -n "${PLOT_BANDS_FILE:-}" ] && [ ! -f "$PLOT_BANDS_FILE" ]; then
        plot_note_skip "bands: no such file: $PLOT_BANDS_FILE"
        return 1
    fi
    src=${PLOT_BANDS_FILE:-$(ls "$proj"/bands/*.dat "$proj"/bands/*.gnu 2>/dev/null | head -1)}
    if [ -z "$src" ] || [ ! -f "$src" ]; then
        plot_note_skip "bands: no band-structure data. PseudoForge does not compute one -- run pw.x with calculation='bands' and bands.x, then point --plot-bands at its output"
        return 1
    fi
    out=$dir/bands.$PLOT_FORMAT
    local tsv; tsv=$(mktemp)
    # bands.x writes "k  energy" blocks separated by blank lines, one block per
    # band.  Fold them into columns so the common renderer can draw them.
    awk 'BEGIN { b = 1 }
         /^[[:space:]]*$/ { if (n) { b++; n = 0 }; next }
         { k[b, ++n] = $1; e[b, n] = $2; if (n > maxn) maxn = n }
         END {
             printf "# k"
             for (i = 1; i <= b; i++) printf " band%d", i
             printf "\n"
             for (j = 1; j <= maxn; j++) {
                 printf "%s", k[1, j]
                 for (i = 1; i <= b; i++) printf " %s", ((i, j) in e ? e[i, j] : "NaN")
                 printf "\n"
             }
         }' "$src" > "$tsv"
    if plot_series "$out" "band structure" "k" "energy (eV)" "$tsv"; then
        rm -f "$tsv"; PLOT_MADE=$((PLOT_MADE + 1)); printf '%s\n' "$out"; return 0
    fi
    rm -f "$tsv"
    plot_note_skip "bands: the renderer produced nothing"
    return 1
}

# Density of states, from dos.x output: energy, dos, integrated dos.
plot_dos() {
    local proj=$1 dir=$2 src out tsv
    if [ -n "${PLOT_DOS_FILE:-}" ] && [ ! -f "$PLOT_DOS_FILE" ]; then
        plot_note_skip "dos: no such file: $PLOT_DOS_FILE"
        return 1
    fi
    src=${PLOT_DOS_FILE:-$(ls "$proj"/dos/*.dos "$proj"/*.dos 2>/dev/null | head -1)}
    if [ -z "$src" ] || [ ! -f "$src" ]; then
        plot_note_skip "dos: no density-of-states data. PseudoForge does not compute one -- run pw.x then dos.x, and point --plot-dos at the .dos file"
        return 1
    fi
    out=$dir/dos.$PLOT_FORMAT
    tsv=$(mktemp)
    {
        printf '# energy(eV) DOS integrated\n'
        grep -v '^#' "$src" | awk 'NF >= 2 { print }'
    } > "$tsv"
    if plot_series "$out" "density of states" "energy (eV)" "states / eV" "$tsv"; then
        rm -f "$tsv"; PLOT_MADE=$((PLOT_MADE + 1)); printf '%s\n' "$out"; return 0
    fi
    rm -f "$tsv"
    plot_note_skip "dos: the renderer produced nothing"
    return 1
}

# ---------------------------------------------------------------------------
# plot_all <project> -- every plot there is data for.
#
# Always returns 0.  A run that produced correct pseudopotentials has not
# failed because the machine has no plotting program, and a caller that exits
# non-zero over a missing picture would break scripts for no reason.
# ---------------------------------------------------------------------------
plot_all() {
    local proj=$1 dir el backend
    dir=${PLOT_DIR:-$proj/plots}
    PLOT_MADE=0 PLOT_SKIPPED=""

    backend=$(plot_backend)
    if [ "$backend" = none ]; then
        warn "no plotting backend: install gnuplot, or python3 with matplotlib"
        info "  nothing else about this run is affected; the data is in $proj/tests"
        return 0
    fi

    mkdir -p "$dir" || { warn "cannot create $dir"; return 0; }
    debug "plotting with $(plot_backend_label)"

    while IFS= read -r el; do
        [ -n "$el" ] || continue
        plot_logder "$proj" "$el" "$dir" >/dev/null || true
        plot_wfc    "$proj" "$el" "$dir" >/dev/null || true
    done < <(state_list ok 2>/dev/null; state_list ok-warn 2>/dev/null)

    plot_bands "$proj" "$dir" >/dev/null || true
    plot_dos   "$proj" "$dir" >/dev/null || true

    if [ "$PLOT_MADE" -gt 0 ]; then
        ok "$PLOT_MADE plot(s) in $dir"
    else
        info "no plots: there was no data to draw"
    fi
    [ -n "$PLOT_SKIPPED" ] && printf '%s' "$PLOT_SKIPPED" | while IFS= read -r l; do
        [ -n "$l" ] && info "  $l"
    done
    return 0
}
