# ---------------------------------------------------------------------------
# The command table, read out of cli_usage.
#
# cli_usage is the help text a user already sees, so it is the one place the
# list of commands is written down. Generating the reference from it means the
# two cannot disagree.
#
# A usage line looks like:
#     recipe <element>        print the ld1.x deck that would be generated
# i.e. an indented verb, optional argument text, two or more spaces, then the
# description.
# ---------------------------------------------------------------------------
/^cli_usage\(\)/ { inu = 1 }
inu && /^\}/     { inu = 0 }
!inu { next }

/^    [a-z][a-z-]*([ ]+[^ ]+)*[ ][ ]+[A-Za-z]/ {
    line = $0
    sub(/^    /, "", line)

    n = match(line, /[ ][ ]+/)
    if (n == 0) next
    head = substr(line, 1, n - 1)
    desc = substr(line, n + RLENGTH)

    verb = head
    args = ""
    if (match(head, /[ ]/)) {
        verb = substr(head, 1, RSTART - 1)
        args = substr(head, RSTART + 1)
    }

    # Options are listed in the same block; they are handled by the other
    # program, and a leading dash is how they are told apart.
    if (verb ~ /^-/) next

    # A pipe inside a table cell ends the cell, so escape it.
    gsub(/\|/, "\\|", desc)
    gsub(/\|/, "\\|", args)

    printf "| `%s` | %s | %s |\n", verb, (args == "" ? "--" : "`" args "`"), desc
}
