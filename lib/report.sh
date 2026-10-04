# shellcheck shell=bash
# ---------------------------------------------------------------------------
# report.sh -- summary.txt / summary.csv / summary.json / summary.html
#
# The HTML report is deliberately a single self-contained file with inline CSS:
# it has to survive being emailed to a collaborator or dropped into a shared
# drive, and it must render with no network access.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# report_provenance -- the run's identity, as a file rather than as prose.
#
# Written next to the pseudopotentials so it travels with them.  A summary a
# human reads is not enough for reproducing a published result six months
# later: that needs the engine build, the library the parameters came from,
# and the tool version, in a form something else can parse.
#
# Deliberately flat key=value rather than JSON: the tool is pure Bash, and a
# hand-rolled JSON writer is one unescaped quote away from producing a file
# that no parser will read.
# ---------------------------------------------------------------------------
report_provenance() {
    local out=$PROJECT_DIR/PROVENANCE.txt eng
    eng=${SPEC[engine]:-ld1}
    pf_manifest_load
    {
        printf '# %s %s -- run provenance\n' "$PSEUDOFORGE_NAME" "$PSEUDOFORGE_VERSION"
        printf '# Generated %s\n\n' "$(date '+%Y-%m-%d %H:%M:%S %z')"

        printf 'tool.name=%s\n'    "$PSEUDOFORGE_NAME"
        printf 'tool.version=%s\n' "$PSEUDOFORGE_VERSION"

        printf 'engine.id=%s\n'      "$eng"
        printf 'engine.label=%s\n'   "${ENG_LABEL[$eng]:-$eng}"
        local v; v=${ENG_VERSION[$eng]:-}
        [ -z "$v" ] && [ "$eng" = ld1 ] && v=$(deps_ld1_version 2>/dev/null)
        case $v in unknown|'') v=unrecorded ;; esac
        printf 'engine.version=%s\n' "$v"
        printf 'engine.build=%s\n'   "$(eng_build_id "$eng" 2>/dev/null || printf 'unrecorded')"
        printf 'engine.binary=%s\n'  "$(eng_resolve "$eng" 2>/dev/null || printf 'unrecorded')"
        printf 'engine.upstream=%s\n' "${ENG_UPSTREAM[$eng]:-unrecorded}"

        printf 'profile=%s\n'    "${SPEC[profile]}"
        printf 'family=%s\n'     "${SPEC[family]}"
        printf 'functional=%s\n' "$(xc_qe_string "${SPEC[xc]}")"
        printf 'functional.requested=%s\n' "${SPEC[xc]}"
        printf 'relativity=%s\n' "$(rel_canon "${SPEC[rel]}")"
        printf 'source=%s\n'     "${SPEC[source]:-local}"

        # Auto-fixes that changed the physics belong here, not only in the
        # prose of a warning.  Read back from the run record rather than from
        # a variable: the executor runs in a subshell and the variable would
        # not survive to this point.
        #
        # Taken from the note the auto-fix engine actually wrote, per element,
        # rather than by grepping for one phrase it used to use.  The old
        # patterns ("scaled by N", "treated as core") had stopped matching the
        # strategies in use, so a run that widened copper's radii by 12%
        # reported the fix on the console and recorded nothing here -- which is
        # precisely the file that is supposed to outlive the console.
        awk -F'	' '!/^#/ && NF && $11 ~ /auto-fixed/ {
            note = $11
            sub(/^auto-fixed \(/, "", note); sub(/\)[ ]*$/, "", note)
            print "autofix." $1 "=" note
        }' "$PROJECT_STATE" 2>/dev/null

        # Which libxc, if the engine is linked against one -- it changes the
        # answer, so it belongs here rather than being inferred from the build
        # hash alone.
        if [ "$eng" = oncvpsp ] || [ "$eng" = ape ]; then
            printf 'libxc.version=%s\n' "${ENG_VERSION[libxc]:-none}"
        fi

        # Recipes corrected against upstream.  A run that silently used a deck
        # differing from PSlibrary's published one would be a downgrade the
        # output does not admit to, so name the element, the keyword, both
        # values and the reason -- here, where provenance is read.
        local _el _fam _prof _xc _rel _evar _rest _eset _row _f _u _c _why
        if prof_psl_set_r "${SPEC[profile]}" "${SPEC[family]}"; then
            _eset=$REPLY
            while IFS=$'\t' read -r _el _fam _prof _xc _rel _evar _rest; do
                case $_el in ''|\#*) continue ;; esac
                [ -n "$_evar" ] || continue
                _row=$(psl_erratum "$_eset" "$_el" "$_evar") || continue
                IFS=$'\t' read -r _f _u _c _why <<< "$_row"
                printf 'recipe.erratum=%s %s %s: %s corrected from %s to %s\n' \
                       "$_eset" "$_el" "$_evar" "$_f" "$_u" "$_c"
                printf 'recipe.erratum.reason=%s\n' "$_why"
            done < "$PROJECT_STATE"
        fi

        printf '\n# element\tfile\tprovenance\tstatus\n'
        awk -F'\t' '!/^#/ && NF { printf "%s\t%s\t%s\t%s\n", $1, $7, $6, $8 }' "$PROJECT_STATE" 2>/dev/null
    } > "$out"
    printf '%s\n' "$out"
}

# Look up a transferability verdict for an element (or "-" if not tested).
# Field 6 is the method that produced it -- six engines measure six different
# things, and a verdict without its method invites comparing them as if they
# did not.
report_transfer() {
    awk -F'\t' -v el="$1" -v c="$2" '$1 == el { print $c; exit }' \
        "$PROJECT_DIR/tests/transferability.tsv" 2>/dev/null
}
report_cutoff() {
    awk -F'\t' -v el="$1" -v c="$2" '$1 == el { print $c; exit }' \
        "$PROJECT_DIR/tests/cutoffs.tsv" 2>/dev/null
}

report_counts() {   # -> "ok warn fail skip total"
    awk -F'\t' '!/^#/ && NF {
        if ($8 == "ok") o++
        else if ($8 == "ok-warn") w++
        else if ($8 == "skip") s++
        else f++
        n++
    } END { printf "%d %d %d %d %d\n", o+0, w+0, f+0, s+0, n+0 }' "$PROJECT_STATE"
}

report_total_seconds() {
    awk -F'\t' '!/^#/ && NF { t += $10 } END { printf "%d\n", t+0 }' "$PROJECT_STATE"
}

# ---------------------------------------------------------------------------

# Where did this element's parameters come from?  "library" means the library's
# own published deck; "pseudoforge" means our construction, which is a different
# pseudopotential and has to be visible at a glance.
report_params() {
    local v; v=$(state_field "$1" 6)
    case $v in
        library|vendor) printf 'library
' ;;
        pseudoforge)    printf 'PSEUDOFORGE
' ;;
        download)       printf 'downloaded
' ;;
        '')             printf -- '-
' ;;
        *)              printf '%s
' "$v" ;;
    esac
}

report_txt() {
    local out=$PROJECT_DIR/reports/summary.txt
    local o w f s n el
    read -r o w f s n <<<"$(report_counts)"

    {
        printf '================================================================\n'
        printf ' PseudoForge %s -- generation summary\n' "$PSEUDOFORGE_VERSION"
        printf '================================================================\n\n'
        printf ' project      : %s\n' "$PROJECT_DIR"
        printf ' generated    : %s\n' "$(date '+%Y-%m-%d %H:%M:%S %z')"
        printf ' profile      : %s (%s)\n' "${PROF_LABEL[${SPEC[profile]}]}" "$(prof_badge "${SPEC[profile]}")"
        printf ' family       : %s\n' "$(upper "${SPEC[family]}")"
        printf ' functional   : %s\n' "$(xc_explain "${SPEC[xc]}")"
        printf ' relativity   : %s\n' "$(rel_label "${SPEC[rel]}")"
        printf ' UPF format   : v%s\n' "${SPEC[upf]}"
        # Which engine, which version, and which build.  The label alone is not
        # reproducible: a libxc-linked ONCVPSP and a stub-linked one share a name
        # and a version number, and do not make the same file.
        printf ' %-12s : %s
' "engine" "$(eng_provenance "${SPEC[engine]:-ld1}")"
        printf ' wall time    : %s (sum over elements)\n\n' "$(human_time "$(report_total_seconds)")"

        printf ' %-4s %-34s %-9s %-11s %-10s %-12s %s\n' ELEM PSEUDOPOTENTIAL STATUS PARAMS TRANSFER ECUT/RHO NOTE
        printf ' %s\n' "$(printf '%.0s-' $(seq 1 100))"
        awk -F'\t' '!/^#/ && NF { print }' "$PROJECT_STATE" | while IFS=$'\t' read -r el fam prof xc rel var upf st att sec msg; do
            local tv cw cr
            tv=$(report_transfer "$el" 5); cw=$(report_cutoff "$el" 2); cr=$(report_cutoff "$el" 3)
            printf ' %-4s %-34s %-9s %-11s %-10s %-12s %s\n' \
                   "$el" "${upf:--}" "$st" "$(report_params "$el")" "${tv:--}" \
                   "$([ -n "$cw" ] && printf '%s/%s' "$cw" "$cr" || printf '-')" \
                   "$(printf '%s' "${msg}" | cut -c1-60)"
        done

        printf '\n %s\n' "$(printf '%.0s-' $(seq 1 100))"
        printf ' %d succeeded, %d succeeded with warnings, %d failed, %d skipped (%d total)\n' "$o" "$w" "$f" "$s" "$n"

        # Name the analysis behind the TRANSFER column.  Six engines measure
        # six different things -- ld1 re-solves unfitted configurations, GTH
        # reports fit residuals, uspp only looks for ghosts -- and a bare
        # verdict invites reading them as one scale. The methods actually used
        # are read back from the results file rather than assumed, so a run
        # that fell back to something else still reports honestly.
        if [ -s "$PROJECT_DIR/tests/transferability.tsv" ]; then
            local methods
            methods=$(awk -F'	' 'NF >= 6 && $6 != "" { print $6 }'                       "$PROJECT_DIR/tests/transferability.tsv" | sort -u | paste -sd', ' -)
            [ -n "$methods" ] &&                 printf '
 TRANSFER measured by: %s
' "$methods"
        fi

        if [ "$f" -gt 0 ]; then
            printf '\n FAILED ELEMENTS\n'
            awk -F'\t' '!/^#/ && NF && $8 != "ok" && $8 != "ok-warn" && $8 != "skip" {
                printf "   %-4s %s\n", $1, $11 }' "$PROJECT_STATE"
            printf '\n Logs for the failures are in %s/logs/.\n' "$PROJECT_DIR"
        fi

        # Ask the question the note answers: was something other than the
        # requested functional actually used?  Keying off XC_STATUS alone
        # ignores the engine, and AtomPAW really does generate meta-GGA --
        # so an AtomPAW r2SCAN run printed "generated natively by AtomPAW"
        # and then denied it in the next sentence.
        if [ "$(xc_generator "${SPEC[xc]}")" != "${SPEC[xc]}" ]; then
            printf '\n NOTE ON THE FUNCTIONAL\n'
            printf '   %s\n' "$(xc_explain "${SPEC[xc]}")"
            printf '   The UPF files carry dft=%s. Use them with %s in pw.x; that is\n' \
                   "$(xc_qe_string "${SPEC[xc]}")" "${XC_QE[${SPEC[xc]}]}"
            printf '   standard practice, but the pseudopotential was not generated\n'
            printf '   self-consistently with %s.\n' "${XC_QE[${SPEC[xc]}]}"
        fi
        if [ "${PROF_PROVENANCE[${SPEC[profile]}]}" = derived ]; then
            printf '\n NOTE ON THE PROFILE\n'
            printf '   %s\n' "${PROF_NOTES[${SPEC[profile]}]}"
        fi
        printf '\n'
    } > "$out"
    printf '%s\n' "$out"
}

# ---------------------------------------------------------------------------
report_csv() {
    local out=$PROJECT_DIR/reports/summary.csv
    {
        printf 'element,Z,pseudopotential,family,profile,functional,functional_status,relativity,variant,status,attempts,seconds,transferability,max_dE_Ry,ecutwfc,ecutrho,message\n'
        awk -F'\t' '!/^#/ && NF { print }' "$PROJECT_STATE" |
        while IFS=$'\t' read -r el fam prof xc rel var upf st att sec msg; do
            printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
                "$(csv_escape "$el")" "${EL_Z[$el]:-}" "$(csv_escape "$upf")" \
                "$(csv_escape "$fam")" "$(csv_escape "$prof")" \
                "$(csv_escape "${XC_QE[$xc]:-$xc}")" "$(csv_escape "${XC_STATUS[$xc]:-}")" \
                "$(csv_escape "$rel")" "$(csv_escape "$var")" "$(csv_escape "$st")" \
                "$att" "$sec" \
                "$(csv_escape "$(report_transfer "$el" 5)")" \
                "$(csv_escape "$(report_transfer "$el" 3)")" \
                "$(csv_escape "$(report_cutoff "$el" 2)")" \
                "$(csv_escape "$(report_cutoff "$el" 3)")" \
                "$(csv_escape "$msg")"
        done
    } > "$out"
    printf '%s\n' "$out"
}

# ---------------------------------------------------------------------------
report_json() {
    local out=$PROJECT_DIR/reports/summary.json
    local o w f s n first=1
    read -r o w f s n <<<"$(report_counts)"
    {
        printf '{\n'
        printf '  "pseudoforge_version": "%s",\n' "$PSEUDOFORGE_VERSION"
        printf '  "generated": "%s",\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')"
        printf '  "project": "%s",\n' "$PROJECT_DIR"
        printf '  "settings": {\n'
        printf '    "profile": "%s",\n' "${SPEC[profile]}"
        printf '    "profile_provenance": "%s",\n' "${PROF_PROVENANCE[${SPEC[profile]}]}"
        printf '    "family": "%s",\n' "${SPEC[family]}"
        printf '    "functional": "%s",\n' "${SPEC[xc]}"
        printf '    "functional_status": "%s",\n' "${XC_STATUS[${SPEC[xc]}]}"
        printf '    "dft_string": "%s",\n' "$(xc_qe_string "${SPEC[xc]}")"
        printf '    "relativity": "%s",\n' "${SPEC[rel]}"
        printf '    "upf_version": %s\n' "${SPEC[upf]}"
        printf '  },\n'
        printf '  "summary": { "ok": %d, "ok_with_warnings": %d, "failed": %d, "skipped": %d, "total": %d },\n' \
               "$o" "$w" "$f" "$s" "$n"
        printf '  "elements": [\n'
        awk -F'\t' '!/^#/ && NF { print }' "$PROJECT_STATE" |
        while IFS=$'\t' read -r el fam prof xc rel var upf st att sec msg; do
            [ "$first" = 1 ] || printf ',\n'
            first=0
            printf '    { "element": "%s", "Z": %s, "pseudopotential": "%s", "status": "%s", "attempts": %s, "seconds": %s, "transferability": "%s", "max_dE_Ry": "%s", "ecutwfc": "%s", "ecutrho": "%s", "message": "%s" }' \
                "$el" "${EL_Z[$el]:-0}" "$upf" "$st" "${att:-0}" "${sec:-0}" \
                "$(report_transfer "$el" 5)" "$(report_transfer "$el" 3)" \
                "$(report_cutoff "$el" 2)" "$(report_cutoff "$el" 3)" \
                "$(printf '%s' "$msg" | sed 's/\\/\\\\/g; s/"/\\"/g')"
        done
        printf '\n  ]\n}\n'
    } > "$out"
    printf '%s\n' "$out"
}

# ---------------------------------------------------------------------------
report_html() {
    local out=$PROJECT_DIR/reports/summary.html
    local o w f s n
    read -r o w f s n <<<"$(report_counts)"

    {
cat <<'HTMLHEAD'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>pseudoforge report</title>
<style>
  :root {
    --bg:#ffffff; --fg:#1a1d21; --muted:#5b6570; --line:#e3e7eb; --card:#f7f9fb;
    --ok:#15803d; --okbg:#dcfce7; --warn:#a16207; --warnbg:#fef3c7;
    --fail:#b91c1c; --failbg:#fee2e2; --skip:#475569; --skipbg:#e2e8f0;
    --accent:#1d4ed8;
  }
  @media (prefers-color-scheme: dark) {
    :root {
      --bg:#0f1419; --fg:#e6e9ec; --muted:#9aa4af; --line:#232a31; --card:#161c23;
      --ok:#4ade80; --okbg:#14321f; --warn:#fbbf24; --warnbg:#3a2e0b;
      --fail:#f87171; --failbg:#3b1418; --skip:#94a3b8; --skipbg:#1e293b;
      --accent:#60a5fa;
    }
  }
  * { box-sizing:border-box; }
  body { margin:0; padding:2rem 1.25rem 4rem; background:var(--bg); color:var(--fg);
         font:15px/1.55 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif; }
  .wrap { max-width:1180px; margin:0 auto; }
  h1 { font-size:1.6rem; margin:0 0 .25rem; letter-spacing:-.01em; }
  h2 { font-size:1.05rem; margin:2.5rem 0 .75rem; text-transform:uppercase;
       letter-spacing:.08em; color:var(--muted); font-weight:600; }
  .sub { color:var(--muted); margin:0 0 2rem; font-size:.92rem; }
  .cards { display:grid; grid-template-columns:repeat(auto-fit,minmax(150px,1fr)); gap:.75rem; }
  .card { background:var(--card); border:1px solid var(--line); border-radius:10px; padding:.9rem 1rem; }
  .card .n { font-size:1.9rem; font-weight:650; line-height:1.1; }
  .card .l { color:var(--muted); font-size:.8rem; text-transform:uppercase; letter-spacing:.06em; }
  dl.meta { display:grid; grid-template-columns:max-content 1fr; gap:.35rem 1.25rem; margin:0;
            background:var(--card); border:1px solid var(--line); border-radius:10px; padding:1rem 1.25rem; }
  dl.meta dt { color:var(--muted); font-size:.85rem; }
  dl.meta dd { margin:0; font-size:.9rem; word-break:break-word; }
  .scroll { overflow-x:auto; border:1px solid var(--line); border-radius:10px; }
  table { border-collapse:collapse; width:100%; font-size:.88rem; }
  th, td { text-align:left; padding:.55rem .8rem; border-bottom:1px solid var(--line); white-space:nowrap; }
  th { background:var(--card); font-weight:600; font-size:.78rem; text-transform:uppercase;
       letter-spacing:.05em; color:var(--muted); position:sticky; top:0; }
  tr:last-child td { border-bottom:none; }
  td.msg { white-space:normal; min-width:18rem; color:var(--muted); font-size:.83rem; }
  .pill { display:inline-block; padding:.12rem .55rem; border-radius:999px; font-size:.78rem; font-weight:600; }
  .ok   { color:var(--ok);   background:var(--okbg); }
  .warn { color:var(--warn); background:var(--warnbg); }
  .fail { color:var(--fail); background:var(--failbg); }
  .skip { color:var(--skip); background:var(--skipbg); }
  .note { border-left:3px solid var(--accent); background:var(--card); padding:.85rem 1.1rem;
          border-radius:0 8px 8px 0; margin:1rem 0; font-size:.9rem; }
  code { font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace; font-size:.86em; }
  ol.refs { padding-left:1.2rem; }
  ol.refs li { margin:.6rem 0; line-height:1.45; }
  ol.refs a { color:var(--accent); word-break:break-all; }
  .muted { color:var(--muted); font-size:.85rem; }
  footer { margin-top:3rem; color:var(--muted); font-size:.82rem; border-top:1px solid var(--line); padding-top:1rem; }
</style>
</head>
<body><div class="wrap">
HTMLHEAD

        printf '<h1>Pseudopotential generation report</h1>\n'
        printf '<p class="sub">%s &middot; PseudoForge %s &middot; %s</p>\n' \
               "$(html_escape "$PROJECT_DIR")" "$PSEUDOFORGE_VERSION" "$(date '+%Y-%m-%d %H:%M')"

        printf '<div class="cards">\n'
        printf '<div class="card"><div class="n" style="color:var(--ok)">%d</div><div class="l">succeeded</div></div>\n' "$o"
        printf '<div class="card"><div class="n" style="color:var(--warn)">%d</div><div class="l">with warnings</div></div>\n' "$w"
        printf '<div class="card"><div class="n" style="color:var(--fail)">%d</div><div class="l">failed</div></div>\n' "$f"
        printf '<div class="card"><div class="n" style="color:var(--skip)">%d</div><div class="l">skipped</div></div>\n' "$s"
        printf '<div class="card"><div class="n">%s</div><div class="l">wall time</div></div>\n' "$(human_time "$(report_total_seconds)")"
        printf '</div>\n'

        printf '<h2>Settings</h2>\n<dl class="meta">\n'
        printf '<dt>Profile</dt><dd>%s <span class="pill skip">%s</span></dd>\n' \
               "$(html_escape "${PROF_LABEL[${SPEC[profile]}]}")" "$(prof_badge "${SPEC[profile]}")"
        printf '<dt>Family</dt><dd>%s</dd>\n' "$(upper "${SPEC[family]}")"
        printf '<dt>Functional</dt><dd>%s</dd>\n' "$(html_escape "$(xc_explain "${SPEC[xc]}")")"
        printf '<dt>Relativity</dt><dd>%s</dd>\n' "$(html_escape "$(rel_label "${SPEC[rel]}")")"
        printf '<dt>UPF format</dt><dd>v%s</dd>\n' "${SPEC[upf]}"
        printf '<dt>%s</dt><dd><code>%s</code></dd>\n' \
               "$(html_escape "${ENG_LABEL[${SPEC[engine]:-ld1}]:-engine}")" \
               "$(html_escape "$(eng_resolve "${SPEC[engine]:-ld1}" 2>/dev/null || echo "${LD1_BIN:-not set}")")"
        [ -n "${PROF_REFERENCE[${SPEC[profile]}]:-}" ] && \
            printf '<dt>Reference</dt><dd><code>%s</code></dd>\n' "$(html_escape "${PROF_REFERENCE[${SPEC[profile]}]}")"
        printf '</dl>\n'

        if [ "${XC_STATUS[${SPEC[xc]}]}" = proxy ]; then
            printf '<div class="note"><strong>Functional provenance.</strong> %s The UPF files carry <code>dft=%s</code>; use them with <code>%s</code> in <code>pw.x</code>.</div>\n' \
                   "$(html_escape "$(xc_explain "${SPEC[xc]}")")" \
                   "$(xc_qe_string "${SPEC[xc]}")" "${XC_QE[${SPEC[xc]}]}"
        fi
        if [ "${PROF_PROVENANCE[${SPEC[profile]}]}" = derived ]; then
            printf '<div class="note"><strong>Derived profile.</strong> %s</div>\n' \
                   "$(html_escape "${PROF_NOTES[${SPEC[profile]}]}")"
        fi

        printf '<h2>Elements</h2>\n<div class="scroll"><table>\n'
        printf '<thead><tr><th>Z</th><th>Element</th><th>Pseudopotential</th><th>Status</th>'
        printf '<th>Transferability</th><th>max |dE| (Ry)</th><th>ecutwfc</th><th>ecutrho</th><th>Time</th><th>Notes</th></tr></thead>\n<tbody>\n'
        awk -F'\t' '!/^#/ && NF { print }' "$PROJECT_STATE" |
        while IFS=$'\t' read -r el fam prof xc rel var upf st att sec msg; do
            local cls tv tde cw cr tcls
            case $st in
                ok)      cls=ok ;;
                ok-warn) cls=warn ;;
                skip)    cls=skip ;;
                *)       cls=fail ;;
            esac
            tv=$(report_transfer "$el" 5); tde=$(report_transfer "$el" 3)
            cw=$(report_cutoff "$el" 2);   cr=$(report_cutoff "$el" 3)
            case $tv in
                excellent|good) tcls=ok ;;
                marginal)       tcls=warn ;;
                poor)           tcls=fail ;;
                *)              tcls=skip ;;
            esac
            printf '<tr><td>%s</td><td><strong>%s</strong></td><td><code>%s</code></td>' \
                   "${EL_Z[$el]:-}" "$el" "$(html_escape "${upf:--}")"
            printf '<td><span class="pill %s">%s</span></td>' "$cls" "$st"
            printf '<td>%s</td>' "$([ -n "$tv" ] && printf '<span class="pill %s">%s</span>' "$tcls" "$tv" || printf '&ndash;')"
            printf '<td>%s</td><td>%s</td><td>%s</td><td>%s</td>' \
                   "${tde:-&ndash;}" "${cw:-&ndash;}" "${cr:-&ndash;}" "$(human_time "${sec:-0}")"
            printf '<td class="msg">%s</td></tr>\n' "$(html_escape "$msg")"
        done
        printf '</tbody></table></div>\n'

        if [ -s "$PROJECT_DIR/tests/cutoffs.tsv" ]; then
            printf '<h2>Recommended cutoffs</h2>\n<div class="note">Lowest cutoff at which the total energy of a generic fcc test cell is converged to within %s mRy/atom. Per-element scan data is in <code>tests/cutoff-&lt;element&gt;.tsv</code>.</div>\n' \
                   "${CUTOFF_TOL_MRY:-1.0}"
        fi

        # ---- References --------------------------------------------------
        #
        # A report that tells you a pseudopotential is good, without telling you
        # whose work it is, is half a report.  DOIs are linked so the reference
        # can be checked rather than trusted.
        local _prof=${SPEC[profile]} _eng=${SPEC[engine]:-} _id _cite _doi _n=0
        printf '<h2>References</h2>\n'
        printf '<div class="note">Cite these for the pseudopotentials in this project. '
        printf 'The same text is in <code>pseudos/CITATION.txt</code>, and the licence terms are in <code>pseudos/LICENSE.txt</code>.</div>\n'
        printf '<ol class="refs">\n'
        while read -r _id; do
            [ -n "$_id" ] || continue
            _n=$((_n + 1))
            _cite=$(md_citation "$_id")
            _doi=$(md_doi_url "$_id")
            printf '<li>%s' "$(html_escape "$_cite")"
            [ -n "$_doi" ] && printf ' <a href="%s" rel="noopener">%s</a>' \
                "$(html_escape "$_doi")" "$(html_escape "$_doi")"
            printf '<br><span class="muted">licence: %s</span></li>\n' \
                "$(html_escape "$(md_license "$_id")")"
        done < <(md_citation_set "$_prof" "$_eng")
        if [ "$_n" = 0 ]; then
            printf '<li>PseudoForge has no verified citation for this selection. Check the distribution these files came from.</li>\n'
        fi
        printf '</ol>\n'
        if [ -n "${MD_NOTE[$_prof]:-}" ]; then
            printf '<div class="note">%s</div>\n' "$(html_escape "${MD_NOTE[$_prof]}")"
        fi

        printf '<footer>Generated by PseudoForge %s. ld1.x is part of Quantum ESPRESSO. ' "$PSEUDOFORGE_VERSION"
        printf 'Recipes for <code>psl-*</code> profiles are reproduced from PSlibrary by Andrea Dal Corso (GPL-2.0-or-later).</footer>\n'
        printf '</div></body></html>\n'
    } > "$out"
    printf '%s\n' "$out"
}

# ---------------------------------------------------------------------------
report_all() {
    banner "Reports"
    local t c j h
    t=$(report_txt); c=$(report_csv); j=$(report_json); h=$(report_html)
    local pv; pv=$(report_provenance)
    info "text : $t"
    info "csv  : $c"
    info "json : $j"
    info "html : $h"
    info "prov : $pv"
    [ "$PF_QUIET" = 1 ] || { printf '\n'; cat "$t"; }
}
