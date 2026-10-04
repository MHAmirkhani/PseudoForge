# ---------------------------------------------------------------------------
# Find unqualified "byte-identical to PSlibrary" claims.
#
# The recipe database is byte-identical to upstream *except* where ERRATA.tsv
# declares otherwise. Stating it without the exception is the kind of overclaim
# that makes everything else on the page less believable.
#
# Two things this must not flag, because both are true without qualification:
#
#   * a saved recipe reproducing its own output byte for byte;
#   * -j 1 and -j 8 producing identical files.
#
# So only lines that mention PSlibrary or upstream are considered, and the
# qualification is looked for in a three-line window -- it is usually the next
# sentence rather than the same one.
#
# tolower() rather than IGNORECASE: the latter is a gawk extension and this
# has to run under mawk too.
# ---------------------------------------------------------------------------
{ buf[NR] = $0 }

END {
    for (n = 1; n <= NR; n++) {
        line = tolower(buf[n])
        if (line !~ /byte.identical|byte for byte/) continue
        if (line !~ /pslibrary|upstream/)           continue

        window = tolower(buf[n] " " buf[n + 1] " " buf[n + 2])
        if (window ~ /errata|except|apart from|bar the|declares/) continue

        print FILENAME ":" n ": " buf[n]
    }
}
