# ---------------------------------------------------------------------------
# The option table, read out of cli_parse.
#
# Every option is a case pattern in one parser, so the parser is the list.
# Whether an option takes a value is decided by whether its branch shifts once
# or twice -- the same thing the parser itself uses to decide, rather than a
# second claim that could disagree with it.
#
# A branch may run over several lines (`-e` does, since it has to clear a
# recipe's element list before appending), so the body is accumulated to its
# `;;` before being read. Looking at the first line alone reported `-e` as
# taking no argument, which is exactly the sort of quiet wrongness a generated
# table is supposed to prevent.
# ---------------------------------------------------------------------------
/^cli_parse\(\)/ { inp = 1 }
inp && /^\}/     { inp = 0 }
!inp { next }

# Collecting the body of a branch that has not reached ;; yet.
collecting {
    body = body " " $0
    if ($0 ~ /;;/) { emit(pat, body); collecting = 0 }
    next
}

/^[ \t]+-[^)]*\)/ {
    pat = $0
    sub(/\).*/, "", pat)
    gsub(/^[ \t]+/, "", pat)
    if (pat !~ /^-/) next
    if (pat ~ /\*/) next                    # the catch-all, not an option

    body = $0
    sub(/^[^)]*\)[ \t]*/, "", body)
    if ($0 ~ /;;/) { emit(pat, body) } else { collecting = 1 }
}

function emit(pat, body,   arg, sets) {
    arg = (body ~ /shift 2/) ? "yes" : "no"

    # What the branch assigns, where that is a single obvious thing. Anything
    # more involved is left as "--" rather than guessed at.
    sets = "--"
    if (match(body, /SPEC\[[a-z_]+\]/))         sets = substr(body, RSTART, RLENGTH)
    else if (match(body, /[A-Z_][A-Z_0-9]*=/))  sets = substr(body, RSTART, RLENGTH - 1)

    gsub(/\|/, "`, `", pat)
    printf "| `%s` | %s | `%s` |\n", pat, arg, sets
}
