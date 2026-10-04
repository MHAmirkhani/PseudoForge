# Use the website

<https://pseudo.amirkhani.me> — pick an element, choose the physics, get a
file. Or find out what to run on your own machine, which is the honest answer
for anything that needs an engine.

## What the site can and cannot do

| | |
|---|---|
| Download a pre-built file | yes |
| Convert it to another format | yes, where the conversion is honest |
| Validate a file you have | yes, structurally |
| Compare two files | yes, with one command locally |
| **Generate a new pseudopotential** | **no — that runs on your machine** |

The server is one core with no engines. It is a shop front and a converter, and
it says so rather than queueing work nothing will collect.
[Why](../architecture/http.md).

## Pick an element

The front page is a periodic table. Click an element; the panel below fills in.

Under it, six selectors — functional, family, relativity, library, engine,
format. Each list is fetched from the API, so it is what this server actually
knows about rather than a list that went stale.

The functional selector marks anything generated **via a proxy**. A meta-GGA
dataset made with PBE is standard practice and perfectly usable — but it is
worth knowing before you download it. See [Choose a
functional](choose-a-functional.md).

## Four buttons

### Download from this site

Serves the pre-built native file, or converts one on demand.

If the conversion is exact you get the file. If it is **lossy** you get the
file and a warning naming what was dropped. If it is **refused** you get the
reason:

> An OpenMX `.vps` holds semilocal potentials $V_l(r)$, one curve per channel.
> UPF wants a separable Kleinman–Bylander form: projector functions and a
> $D_{ij}$ matrix. Going from one to the other means choosing a local channel
> and constructing projectors — a new pseudopotential, not a relabelled file.

That is not a missing feature. See [Convert between
formats](convert-formats.md).

### Download from official repo

Opens the authors' own distribution point — PseudoDojo, SSSP, PSlibrary,
GBRV, SG15. PseudoForge mirrors nothing it cannot attribute, and for anything
you intend to publish with, the authors' copy is the one to cite.

### Build locally

Gives you the exact command, copyable:

```bash
pseudoforge generate -e Fe -t paw -p psl-high -x pbe -r scalar -o ./out
```

with links to [installation](../getting-started/installation.md) and the
[tutorials](../tutorials/index.md).

### Compare

The feature worth the trip. Download one file from here and one from the
authors, then:

```bash
pseudoforge compare ./from-this-site.UPF ./from-the-authors.UPF
```

which reports valence charge, projectors, grid and suggested cutoffs.
`--ecut N` compares at one cutoff.

This is how you answer "is the file I just downloaded the same as the published
one?" — a question that is otherwise surprisingly hard to settle.

## The download browser

`/download/` lists everything the server holds: element, functional, family,
relativity, engine, format, size, and whether **provenance was recorded**.

That last column matters. A file whose sidecar is missing shows `none`, and its
attributes read `unknown` rather than being guessed from its name. Prefer files
with recorded provenance; if you need one that has none, treat its labels as
unverified.

## The validator

`/validate/` takes a file and runs the structural checks: the header parses,
the valence charge is positive and plausible for the element, the grid is
monotonic, the projector count matches `l_max`.

These need no engine, which is why the server can run them. They are also the
checks that catch the worst class of problem — a file an engine wrote
successfully and exited 0 on, which no code can use.

**Transferability is a different question.** It needs the atomic code, so run
it locally:

```bash
pseudoforge validate ./Si.UPF
pseudoforge import ./a-directory-of-pseudos -o ./audit
```

Nothing you upload is stored. 8 MB limit.

## The documentation

`/docs/` is the full documentation on the same domain — search covers it, and
every page links back to the application.

## If you hit a limit

**429** — 60 requests a minute per IP, and 2 per second at the edge. One core.

**503 on a conversion** — that converter is not installed on the server. The
response names which one.

**501 on generate** — expected. Install PseudoForge and run it locally; the
command is on the page.

## Using the API directly

Everything the site does is a documented endpoint:

```bash
curl -s https://pseudo.amirkhani.me/api/native | jq '.[0]'
curl -s https://pseudo.amirkhani.me/api/formats | jq '.conversions'
curl -s -X POST https://pseudo.amirkhani.me/api/convert \
     -H 'Content-Type: application/json' \
     -d '{"id":"Si.pbe-n-kjpaw_psl.1.0.0.UPF","to":"xml"}'
```

See the [HTTP API reference](../reference/http-api.md). The same calls work
locally with no server at all:

```bash
pseudoforge api GET /api/native
```

because the website is a [fourth interface on the same
core](../architecture/http.md), not a separate service.

## Running it yourself

```bash
deploy/scripts/serve-local.sh          # -> http://127.0.0.1:8080
```

The whole site on your own machine: the frontend at `/`, the documentation at
`/docs/`, the API proxied at `/api/`.

`POST /api/generate` still answers 501 there. The endpoint refuses
unconditionally rather than checking whether engines happen to be present --
one behaviour everywhere is easier to rely on than an endpoint that means
different things on different machines. Generate with the command line:

```bash
pseudoforge generate -e Si -t paw -p psl-high -x pbe -o ./out
```
