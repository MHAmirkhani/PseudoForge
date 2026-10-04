# The native store

PseudoForge ships a pre-built store of pseudopotential files. It is what
the website serves and what `pseudoforge native` reads. This page is
how it is organised, how to query it, and how to rebuild a piece of it.

It is **not** a source tree: nothing in the store is generated at request
time. Every file was produced by a run of the tool, and the run's record
(`reports/summary.json`, `logs/`, the file's own provenance) travels
with it.

## Where it lives

```text
~/pf-native/                    the store itself
~/pf-var/native -> ~/pf-native  what the server reads through
```

The symlink exists because `deploy/scripts/serve-local.sh` expects the
store under `PF_VAR_DIR`, and building it somewhere else is common enough
that the path was worth separating from the location.

## What is in it

| Metric | Value |
|---|---|
| Indexed pseudopotential files | 29,647 |
| Total files on disk | 84,181 |
| Pseudopotential size (gzipped) | 17.6 GB |
| Total size | 23 GB |
| Unique elements | 103 (the whole table) |
| Unique profiles | 17 |
| Unique formats | 17 |
| Engine × family × functional × relativity combinations | 87 |

The two file counts answer different questions.  **29,647** is what
`index.tsv` lists -- files a user can download, one per pseudopotential.
**84,181** is every regular file under the store root: the same 29,647
plus each run's `PROVENANCE.txt`, `manifest`, `state.tsv`, `logs/`,
`reports/`, `inputs/` and the `tests/transferability.tsv` the run wrote
beside its output.  The site's download page reads the index, so it
counts 29,647; `du -sh` counts 84,181.

The counts come from `find ~/pf-native -type f | wc -l` and from the
index; the store is rebuilt from time to time as engines change, so a
reader who needs a number should read it, not quote this page.

### What is not in it

APE. Its GGA path has no solution for an open d shell (Ti, Fe, Cu, Zn,
Ag all fail) and its LDA path is covered by `ld1`. The store does
not grow for no new coverage. Run `pseudoforge engines build ape` and
use it locally if a libxc functional no other engine carries is what you
need. See [the APE page](engines/ape.md).

## Layout

Every file sits at a path that names the four things that decide what it
is:

```text
<profile>/<family>/<xc>/<relativity>/pseudos/<Element>.<tags>.<format>[.gz]
```

For example:

```text
psl-high/nc/pbe/scalar/pseudos/Si.pbe-n-rrkjus_psl.1.0.0.UPF.gz
opium/nc/pz/full/pseudos/Ag.rel-pz-opium.vps.gz
atompaw/paw/r2scan/nonrel/pseudos/Fe.r2scan-atompaw.xml.gz
```

The four path components are the four filters the site offers, and the
same four that appear in the index and in `pseudoforge native list`.

Alongside `pseudos/`, each `<xc>/<relativity>/` directory holds:

| Path | Contents |
|---|---|
| `pseudos/` | The pseudopotential files themselves, gzipped |
| `reports/summary.json` | The run's record: counts, timings, the exact command |
| `reports/summary.txt` | The same, human-readable |
| `reports/summary.csv` | One row per element |
| `reports/summary.html` | The same, for a browser |
| `logs/<Element>.log` | The engine's own output for that element |

The `.log` files are the raw record. When something looks wrong in a
file, they are what to read first.

## How it is indexed

The store has one index, `~/pf-native/index.tsv`, thirteen tab-separated
columns and one row per file:

```text
#id  element  xc  family  relativity  engine  format  profile  encoding
     path  size  sha256  provenance
```

The first line is a comment and starts with `#`, which is why every
reader of the file skips it. `id` is derived from the file's own path,
so it is stable across rebuilds as long as the file does not move.

The index is rebuilt with:

```bash
pseudoforge native index
pseudoforge native index /path/to/other/store
```

Nothing else reads `index.tsv` directly. The site, the CLI and the API
all go through it, so an index that is out of date shows up as files that
exist on disk but not in the site, or the reverse.

## How it is built

Each `profile × family × functional × relativity` combination is a *stamp*.
A stamp is an empty file under `~/pf-native/.stamps/` named for the
combination:

```text
~/pf-native/.stamps/
  adpack.nc.pbe.full
  atompaw.paw.pbe.scalar
  atompaw.paw.r2scan.nonrel
  ...
```

The file's modification time is when the combination was last built. A
rebuild skips a combination whose stamp is newer than the recipe database
for that profile, which is what makes `tools/build-native-store.sh`
resumable: stop it half way, run it again, and it picks up where it left
off.

To force a combination to rebuild, delete its stamp:

```bash
rm ~/pf-native/.stamps/opium.nc.pz.full
tools/build-native-store.sh
```

A file that a run could not produce -- an element an engine cannot
handle, a functional the engine does not implement -- is recorded in
the run's report and named in `~/pf-native/.rejected/`. The store does
not carry a placeholder for it. See [Limitations](limitations.md) for the
reasons a run refuses, and [Coverage](coverage.md) for what a given
profile covers.

## Reading it

### From the CLI

```bash
pseudoforge native list                 # every file in the store
pseudoforge native list /other/store    # a different store
pseudoforge native size                 # disk usage, against the VPS budget
```

`native list` prints ID, element, xc, family, format, profile and size,
tab-separated, one file per line. It is the same data the site's download
page filters, without the browser.

### Over HTTP

| Endpoint | Returns |
|---|---|
| `GET /api/native` | Every file in the store, as JSON |
| `GET /api/native/:id` | One file: metadata and provenance |
| `GET /api/download/:id` | The file itself, decompressed |

```bash
curl -s http://127.0.0.1:8099/api/native | jq '.files | length'
curl -s http://127.0.0.1:8099/api/native/psl_high_nc_pbe_scalar_pseudos_Si_UPF | jq .
curl -sO http://127.0.0.1:8099/api/download/psl_high_nc_pbe_scalar_pseudos_Si_UPF
```

The `id` in the URL is the same `id` in `index.tsv`, so a file
found with `native list` can be fetched by id without building the
URL by hand.

### On the site

The [download page](https://pseudo.amirkhani.me/download/) crosses the
four path components -- profile, family, functional, relativity -- with
the element, and offers the matching files as one archive or one at a
time. The archive is built on the server, so a request for a hundred
elements does not mean a hundred downloads.

## Serving it locally

The site is three things Nginx puts together on the VPS, and
`serve-local.sh` puts them together on a workstation the same way:

```text
/       -> www/       the frontend        (static)
/docs/  -> docs/      the built MkDocs    (static)
/api/   -> uvicorn    the transport       (proxied)
```

```bash
cd ~/"Pseudo Maker/pseudoforge"
export PF_VAR_DIR=$HOME/pf-var PF_NATIVE_DIR=$HOME/pf-var/native
export PF_DECOMPRESSED_DIR=$HOME/pf-var/decompressed
deploy/scripts/serve-local.sh
# -> http://127.0.0.1:8080
```

Run it inside WSL or Linux, not from PowerShell: `pseudoforge` is a Bash
program and the API shells out to it.

## Rebuilding

The full build is `tools/build-native-store.sh`. It is long -- every
combination in the plan is a run of an engine over every element that
profile covers -- and it is safe to stop and resume.

```bash
cd ~/"Pseudo Maker/pseudoforge"
export PF_VAR_DIR=$HOME/pf-var PF_NATIVE_DIR=$HOME/pf-var/native
tools/build-native-store.sh
```

The XML files that sit alongside the native outputs are produced after
the run, from the UPF files, by `tools/add-xml-to-store.sh`. That
script is idempotent: a file that already has an XML beside it is left
alone. XML is a conversion of the UPF, not an engine's own output, and
the provenance says so.
