# Writing documentation

## Where a page goes

The structure is [Diátaxis](https://diataxis.fr/): four quadrants, and a page
belongs to exactly one. The usual mistake is a tutorial that turns into
reference halfway down.

| Quadrant | Directory | Answers | Written as |
|---|---|---|---|
| **Tutorial** | `tutorials/` | "teach me by doing" | a narrative with real output |
| **How-to** | `how-to/` | "I need to do X" | steps toward one goal |
| **Reference** | `reference/` | "what are the options" | tables, complete, no narrative |
| **Explanation** | `architecture/`, `explanation/` | "why is it like this" | prose, reasoning, trade-offs |

`architecture/` is explanation about the software; `explanation/` is
explanation about the physics and the libraries.

Ask what the reader is doing when they arrive. Someone mid-task wants a
how-to; someone deciding wants explanation; someone with the command half typed
wants reference.

## The rules that are actually enforced

`tests/test_docs.sh` runs on every commit, so these are not style advice.

### Every command must work

Every fenced block containing `pseudoforge` is extracted and checked: the verb
must exist in the dispatch, and every flag must be one the parsers accept.

```bash
bash tests/test_docs.sh
```

This has caught invented flags three times — `--from`, `--tag-suffix` and
`--recipe`'s element semantics were all written into the docs before they
existed, or documented as behaving in a way they did not.

**Run the command before writing it down.** Paste the real output.

### Tutorials are run

Under `PF_SLOW_TESTS=1`, each tutorial's first generate command is executed and
must produce the documented files.

A tutorial that deliberately shows a *refused* command marks it:

````markdown
```bash
# expect: refused
pseudoforge generate -e Si -t paw -x r2scan --engine atompaw -o ./out
```
````

and the refusal is then asserted rather than skipped — a refusal that stopped
happening would be a silent behaviour change.

### Reference tables are generated

`reference/cli.md`, `engines.md`, `formats.md`, `profiles.md` and
`http-api.md` have generated regions:

```markdown
<!-- generated:begin -->
<!-- generated:end -->
```

**Do not edit between the markers.** Change the code, then:

```bash
tools/gen_reference.sh --write
tools/gen_reference.sh --check
```

The generators read the parsers and registries themselves —
`cli_usage`, `cli_parse`, `ENG_*`, `formats.tsv`, the conversion registry, the
HTTP route table. A hand-written flag table is wrong the first time someone
adds a flag, and nobody finds out until a reader types it.

Prose outside the markers is yours and is never touched.

### Claims are qualified where the code qualifies them

The recipe database is byte-identical to upstream **except where `ERRATA.tsv`
declares a correction**. A test greps for the unqualified version of that claim
and fails.

More generally: if the code says "except", the documentation says "except".

### Links resolve

Every relative link is checked in the Markdown, and every link in the **built
HTML** by `tests/test_docs_deploy.sh`. The site is served under `/docs/`, so an
absolute link like `/reference/cli/` works in `mkdocs serve` and 404s on the
deployment — which is why that one is checked specifically.

Use relative links: `../reference/cli.md`.

### Every page is in the navigation

A page not in `mkdocs.yml` is a page nobody finds. Both the missing-page and
the orphan-page directions are checked, and `mkdocs build --strict` fails on
either.

## Adding a page

1. Write it in the right directory.
2. Add it to `nav:` in `mkdocs.yml`.
3. Link to it from somewhere a reader will be.
4. ```bash
   tools/gen_reference.sh --check
   bash tests/test_docs.sh
   MKDOCS_BIN=… bash tests/test_mkdocs.sh
   ```

## Building it

MkDocs is **optional**. The pages are Markdown and read fine in the repository
or on a forge; the site is a nicety, not a dependency.

```bash
python3 -m venv .venv && . .venv/bin/activate
pip install mkdocs mkdocs-material

mkdocs serve                 # http://127.0.0.1:8000
mkdocs build --strict        # into site/
```

`--strict` turns warnings into errors. A broken link should fail a build, not
produce a site with a dead link in it.

## House style

**Say what is true, including when it is inconvenient.** The empty
transferability column, the `Unverified — check the source` citations, the
AtomPAW label bug — these are in the documentation because a reader who
discovers them alone trusts everything else less.

**Show the measurement.** "z_valence = 9.00, 27 SCF iterations, transferability
excellent" beats "works correctly".

**Name the failure mode.** A warning is more useful with the consequence
attached: not "no plotting backend" but "no plotting backend; nothing else
about this run is affected".

**Explain a refusal.** Every refused conversion carries a paragraph on what the
target would have to invent. That paragraph is the documentation.

**Prefer the second person and the active voice.** "Run this", not "this may be
run".

**Avoid the word simply.** If it were simple the page would not exist.
