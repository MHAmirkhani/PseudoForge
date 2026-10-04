#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# extract_pslibrary.sh -- build the PSlibrary recipe database shipped with
# pseudoforge out of the upstream pslibrary .job files.
#
# The upstream .job files are bash scripts that emit ld1.x input decks through
# here-documents.  We slice every here-document out verbatim and store it as a
# template with placeholders, so pseudoforge can regenerate byte-identical inputs
# for any functional / relativity combination without carrying 32k lines of
# shell around.
#
#   {{FCT}}           functional tag used in file names  (pbe, rel-pbe, ...)
#   {{GFUN}}          dft= string handed to ld1.x        (PBE, LDA, ...)
#   {{NREL}}          rel= value                         (1 scalar, 2 full)
#   {{PSDIR}}         pseudopotential directory (tests only)
#   {{FROZEN_CORE}}   frozen_core= value       (tests only)
#
# Slicing is verbatim, which is what lets us say a deck is PSlibrary's and
# mean it.  The few upstream decks that are not merely unusual but impossible
# are corrected afterwards from data/psl/ERRATA.tsv -- declared, reasoned and
# reapplied on every extraction, so a correction cannot be quietly lost the
# next time this script runs.  Every generation deck is then checked for
# configurations that ask for more electrons than the nucleus has, which is
# the defect class ERRATA exists for.
#
# Usage:  tools/extract_pslibrary.sh <path-to-pslibrary.1.0.0> [outdir]
# ---------------------------------------------------------------------------
set -euo pipefail

SRC=${1:?usage: extract_pslibrary.sh <pslibrary dir> [outdir]}
OUT=${2:-data/psl}

SETS="
paw_ps_high.job:paw-high
us_ps_high.job:us-high
paw_ps_low.job:paw-low
us_ps_low.job:us-low
nc_ps_collection.job:nc
paw_ps_collection.job:paw-031
us_ps_collection.job:us-031
paw_ps_collection_alt.job:paw-alt
us_ps_collection_alt.job:us-alt
paw_ps_collection_tot.job:paw-tot
us_ps_collection_tot.job:us-tot
"
TESTSETS="
paw_ps_test_high.job:paw-high
us_ps_test_high.job:us-high
paw_ps_test_low.job:paw-low
us_ps_test_low.job:us-low
paw_ps_test.job:paw-031
us_ps_test.job:us-031
paw_ps_test_alt.job:paw-alt
us_ps_test_alt.job:us-alt
paw_ps_test_tot.job:paw-tot
us_ps_test_tot.job:us-tot
"

# The errata live inside the tree this script rebuilds, so take a copy before
# the wipe and put it back afterwards.  Losing the corrections to the very
# command that is supposed to reapply them would be a poor joke.
ERRATA_SRC=${ERRATA_SRC:-$OUT/ERRATA.tsv}
ERRATA_TMP=$(mktemp)
trap 'rm -f "$ERRATA_TMP"' EXIT
if [ -f "$ERRATA_SRC" ]; then
    cp "$ERRATA_SRC" "$ERRATA_TMP"
else
    echo "warning: no ERRATA.tsv at $ERRATA_SRC -- extracting upstream uncorrected" >&2
    : > "$ERRATA_TMP"
fi

rm -rf "$OUT"
mkdir -p "$OUT"
cp "$ERRATA_TMP" "$OUT/ERRATA.tsv"

# split <jobfile> <destdir> <indexfile> <gen|test>
split_job() {
    local job=$1 dest=$2 idx=$3 kind=$4
    [ -f "$job" ] || { echo "  (skip, missing: $job)" >&2; return 0; }
    mkdir -p "$dest"

    awk -v dest="$dest" -v idxfile="$idx" -v kind="$kind" '
      # Some collection files wrap a recipe in "if [ $nrel = 2 ] ... else ... fi",
      # meaning the recipe applies only to full- (or only to scalar-) relativistic
      # runs.  Track that state so the index can record which one applies.
      /^if \[ \$nrel = 2 \]/           { relcond = "fr"; next }
      /^else[[:space:]]*$/ && relcond  { relcond = "sr"; next }
      /^fi[[:space:]]*$/   && relcond  { relcond = "";   next }

      /^cat > .*\.in << EOF/ {
          name = $3
          sub(/\.in$/, "", name)
          p    = index(name, ".")
          el   = substr(name, 1, p - 1)
          rest = substr(name, p + 1)
          inblock = 1
          body    = ""
          next
      }
      inblock && /^EOF[[:space:]]*$/ {
          inblock = 0
          key = rest
          gsub(/\$fct/, "{{FCT}}", key)
          if (kind == "test") sub(/\.test$/, "", key)

          # Variant tag = semicore tag + upstream version, e.g. "spn.1.0.0".
          # The version keeps recipes distinct that upstream ships side by side
          # for one element (Al ...psl.0.2.2 next to Al ...psl.0.1).
          tag = key
          sub(/^\{\{FCT\}\}-?/, "", tag)
          gsub(/-?(kjpaw_psl|rrkjus_psl|nc)/, "", tag)
          sub(/^-/, "", tag)
          sub(/^\./, "std.", tag)
          if (tag == "") tag = "std"

          out = dest "/" el "." tag (relcond == "" ? "" : "." relcond) ".tpl"
          printf "%s", body > out
          close(out)
          printf "%s\t%s\t%s.%s\t%s\n", el, tag, el, key, (relcond == "" ? "any" : relcond) >> idxfile
          next
      }
      inblock {
          line = $0
          gsub(/\$fct/,         "{{FCT}}",         line)
          gsub(/\$gfun/,        "{{GFUN}}",        line)
          gsub(/\$nrel/,        "{{NREL}}",        line)
          gsub(/\$psdir/,       "{{PSDIR}}",       line)
          gsub(/\$frozen_core/, "{{FROZEN_CORE}}", line)
          body = body line "\n"
          next
      }
    ' "$job"
}

# Upstream emits a handful of recipes twice under the same name; the later
# here-document wins when the job file is sourced, so keep the last one here too.
dedupe_index() {
    local f=$1
    [ -s "$f" ] || return 0
    awk -F'\t' '{ seen[$1 FS $2 FS $4] = $0; order[$1 FS $2 FS $4] = (($1 FS $2 FS $4) in order) ? order[$1 FS $2 FS $4] : ++n }
                END { for (k in seen) lines[order[k]] = seen[k]
                      for (i = 1; i <= n; i++) if (i in lines) print lines[i] }' "$f" > "$f.tmp"
    mv "$f.tmp" "$f"
}

# ---------------------------------------------------------------------------
# apply_errata <outdir>
#
# Reapply the declared corrections in ERRATA.tsv to the freshly sliced
# templates.  A row whose "upstream" text is not found is a hard error: it
# means upstream changed under us, and silently skipping the correction is how
# a fixed recipe regresses without anyone noticing.
# ---------------------------------------------------------------------------
apply_errata() {
    local out=$1 errata=${ERRATA_TMP:-$1/ERRATA.tsv}
    local set el tag field up corr reason tpl n=0
    [ -s "$errata" ] || { echo "  (no errata declared; nothing to correct)"; return 0; }

    while IFS=$'\t' read -r set el tag field up corr reason; do
        case $set in ''|\#*) continue ;; esac
        tpl=$out/$set/$el.$tag.tpl
        if [ ! -f "$tpl" ]; then
            echo "ERRATA: $set/$el.$tag has no template -- upstream no longer ships it" >&2
            return 1
        fi
        if ! grep -qF "$field='$up'" "$tpl"; then
            echo "ERRATA: $set/$el.$tag: upstream $field is no longer '$up'" >&2
            echo "        the correction was written against a different upstream;" >&2
            echo "        recheck it against the new text before extracting again." >&2
            return 1
        fi
        # Rewrite the one keyword, leaving every other byte as upstream wrote
        # it.  Spliced by index/substr rather than sub(): the upstream text
        # contains "[Xe]", which sub() would read as a character class and fail
        # to match -- silently, while still reporting the correction as applied.
        awk -v old="$field='$up'" -v new="$field='$corr'" '
            { p = index($0, old)
              if (p > 0) $0 = substr($0, 1, p - 1) new substr($0, p + length(old))
              print }' "$tpl" > "$tpl.new" && mv "$tpl.new" "$tpl"
        if grep -qF "$field='$up'" "$tpl"; then
            echo "ERRATA: $set/$el.$tag: rewrite did not take" >&2
            return 1
        fi
        printf '  %-10s %-3s %-14s %s: %s -> %s\n' "$set" "$el" "$tag" "$field" "$up" "$corr"
        n=$((n + 1))
    done < "$errata"
    printf '  %d correction(s) applied\n' "$n"
}

# ---------------------------------------------------------------------------
# check_configs <outdir>
#
# A generation deck (iswitch=3) whose config asks for more electrons than the
# nucleus has makes ld1.x compute a core larger than Z and emit a negative
# z_valence -- a file that is written successfully and is unusable.  Negative
# occupations are ld1's marker for an unoccupied channel and contribute zero.
#
# Test decks (iswitch=2) are left alone: a charged reference configuration is a
# legitimate transferability probe, and upstream ships several.
# ---------------------------------------------------------------------------
check_configs() {
    local out=$1 bad=0 f
    for f in "$out"/*/*.tpl; do
        [ -e "$f" ] || continue
        grep -q 'iswitch=3' "$f" || continue
        awk -v f="$f" '
            BEGIN { core["[He]"]=2;  core["[Ne]"]=10; core["[Ar]"]=18
                    core["[Kr]"]=36; core["[Xe]"]=54; core["[Rn]"]=86 }
            /zed=/    { if (match($0, /zed=[0-9.]+/)) { z = substr($0, RSTART+4, RLENGTH-4) + 0 } }
            /config=/ { if (match($0, /config='\''[^'\'']*'\''/)) cfg = substr($0, RSTART+8, RLENGTH-9) }
            END {
                if (cfg == "" || z == 0) exit 0
                n = split(cfg, a, " "); tot = 0
                for (i = 1; i <= n; i++) {
                    t = a[i]
                    if (t in core) { tot += core[t]; continue }
                    if (match(t, /^[0-9]+[spdfg]/)) {
                        occ = substr(t, RLENGTH + 1) + 0
                        if (occ > 0) tot += occ      # negative = unoccupied channel
                    }
                }
                if (tot > z + 0.001) {
                    printf "  IMPOSSIBLE %s\n    zed=%g but config asks for %g electrons: %s\n", f, z, tot, cfg
                    exit 1
                }
            }' "$f" || bad=$((bad + 1))
    done
    if [ "$bad" -gt 0 ]; then
        echo "$bad generation deck(s) ask for more electrons than the nucleus has." >&2
        echo "Each is either an upstream defect needing a row in data/psl/ERRATA.tsv," >&2
        echo "or a sign that the slicing went wrong.  Not shipping it either way." >&2
        return 1
    fi
    echo "  every generation deck has a physically possible configuration"
}

echo "Extracting generation recipes ..."
for pair in $SETS; do
    job=${pair%%:*}; sid=${pair##*:}
    printf '  %-28s -> %s\n' "$job" "$sid"
    : > "$OUT/$sid.index"
    split_job "$SRC/$job" "$OUT/$sid" "$OUT/$sid.index" gen
    dedupe_index "$OUT/$sid.index"
done

echo "Extracting transferability tests ..."
mkdir -p "$OUT/tests"
for pair in $TESTSETS; do
    job=${pair%%:*}; sid=${pair##*:}
    printf '  %-28s -> tests/%s\n' "$job" "$sid"
    : > "$OUT/tests/$sid.index"
    split_job "$SRC/$job" "$OUT/tests/$sid" "$OUT/tests/$sid.index" test
    # record the frozen_core default this test set runs with (upstream sets it
    # at the top of the job file; sets that do not, inherit .false.)
    fc=$(grep -m1 "^frozen_core=" "$SRC/$job" 2>/dev/null | cut -d= -f2 || true)
    echo "${fc:-.false.}" > "$OUT/tests/$sid.frozen_core"
    dedupe_index "$OUT/tests/$sid.index"
done

echo "Applying declared upstream errata ..."
apply_errata "$OUT"

echo "Checking configurations ..."
check_configs "$OUT"

echo
echo "Summary:"
for f in "$OUT"/*.index "$OUT"/tests/*.index; do
    [ -s "$f" ] || continue
    d=$(dirname "$f"); label=$(basename "$f" .index)
    case "$d" in *tests) label="test/$label" ;; esac
    n=$(wc -l < "$f"); files=$(ls "$d/$(basename "$f" .index)" 2>/dev/null | wc -l)
    printf '  %-22s %4d recipes   %4d template files\n' "$label" "$n" "$files"
done
