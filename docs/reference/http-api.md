# HTTP API

The REST interface. Every endpoint calls the same core function the command
line calls — see [The website](../architecture/http.md) for why that matters
and how it is enforced.

The table below is **generated from the route table in `lib/http.sh`** by
`tools/gen_reference.sh`, and `tests/test_docs.sh` fails if what is committed
is not what the code would produce today.

Everything here is also reachable without a server:

```bash
pseudoforge api --routes
pseudoforge api GET /api/engines
pseudoforge api POST /api/convert body.json
```

<!-- generated:begin -->
<!-- Do not edit between these markers: tools/gen_reference.sh writes them. -->

| Method | Path | What it does |
|---|---|---|
| `GET` | `/api/health` | Environment and engine availability, as doctor records |
| `GET` | `/api/version` | Tool version and name |
| `GET` | `/api/routes` | Every route in the REST API |
| `GET` | `/api/engines` | Every engine in the registry |
| `GET` | `/api/engines/:name` | One engine: families, formats, licence, upstream |
| `GET` | `/api/formats` | Every format, and every conversion path with its cost |
| `GET` | `/api/profiles` | Every library profile |
| `GET` | `/api/xc` | Every exchange-correlation functional |
| `GET` | `/api/elements` | The element table |
| `GET` | `/api/elements/:symbol` | Native files and profiles for one element |
| `GET` | `/api/advise` | Physics-reasoned pseudopotential recommendation |
| `POST` | `/api/advise` | Physics-reasoned pseudopotential recommendation |
| `GET` | `/api/coverage` | Element x profile coverage matrix |
| `GET` | `/api/recent` | Recently added files in the store |
| `GET` | `/api/native` | Native files available on this server |
| `GET` | `/api/native/:id` | One native file: metadata and provenance |
| `GET` | `/api/provenance/:id` | Show provenance for a native file |
| `POST` | `/api/convert` | Convert a native file to another format |
| `GET` | `/api/download/:id...` | Serve a native or converted file |
| `POST` | `/api/validate` | Validate an uploaded pseudopotential |
| `POST` | `/api/generate` | Refused here: generation is a local operation |

<!-- generated:end -->


---

## Read endpoints

None of these needs an engine, which is why they work on a server that has
none.

### `GET /api/health`

`doctor_checks`, as JSON. The same records the CLI prints and the wizard
panel shows.

```json
[
  {"category":"engine","name":"Quantum ESPRESSO ld1.x","status":"ok",
   "detail":"/opt/espresso/7.6/ld1.x","fix":""},
  {"category":"plotting","name":"backend","status":"optional",
   "detail":"none: --plot will say so and carry on","fix":"install gnuplot"}
]
```

`status` is one of `ok`, `missing`, `optional`, `info`. On the public server
most engines are `missing`, and that is correct: it does not have them.

### `GET /api/engines` · `GET /api/engines/:name`

```json
{"id":"oncvpsp","label":"ONCVPSP (Hamann)","families":"nc",
 "native_upf":"yes","licence":"GPL-3.0",
 "upstream":"https://github.com/oncvpsp/oncvpsp",
 "available":false,"note":"..."}
```

`available` is whether the binary is present **on this server**. On the public
deployment it is `false` for every engine — see
[the engine pages](engines.md) for what each one does.

An unknown name is `404` and lists the ones that exist.

### `GET /api/formats`

Both halves of the format question: what can be written, and what can be
converted into what.

```json
{"formats":[{"id":"upf","label":"UPF (Quantum ESPRESSO v2)","engines":"ld1 oncvpsp ...","extension":"UPF"}],
 "conversions":[{"from":"gth","to":"upf","kind":"refused","tool":"none","note":"A GTH file is a dozen analytic coefficients ..."}]}
```

`kind` is `exact`, `lossy` or `refused`. A refusal carries its reason.

### `GET /api/profiles` · `GET /api/xc` · `GET /api/elements`

The library, functional and element registries. `xc` carries `status`, which is
`native` or `proxy` — a meta-GGA served through a proxy is a real thing to know
before downloading it.

### `GET /api/native` · `GET /api/native/:id`

What this server actually holds.

```json
{"id":"Si.pbe-n-kjpaw_psl.1.0.0.UPF","element":"Si","xc":"pbe","family":"paw",
 "relativity":"scalar","engine":"ld1","format":"upf","size":1315611,
 "sha256":"…","has_provenance":true}
```

`has_provenance:false` means the file arrived without its sidecar and its
attributes read `unknown`. They are not guessed from the file name.

`503` with `native_index_unavailable` means the server has no index yet.

---

## Convert

### `POST /api/convert`

```json
{"id": "Si.pbe-n-kjpaw_psl.1.0.0.UPF", "to": "xml"}
```

| Status | Meaning |
|---|---|
| `200` | converted, or already cached |
| `400` | missing fields, or no such conversion path |
| `404` | no native file with that id |
| `409` | **refused** — the reason is in the body |
| `500` | the converter ran and produced nothing |
| `503` | the converter is not installed here |

```json
{"id":"…","from":"upf","to":"xml","kind":"exact","tool":"upfconv",
 "size":1315611,"download":"/api/download/…/Si.pbe-n-kjpaw_psl.1.0.0.xml",
 "warnings":""}
```

A `lossy` conversion fills `warnings` with what was dropped. A `409` carries
the core's full reason:

```json
{"error":"conversion_refused","from":"vps","to":"upf","kind":"refused",
 "reason":"An OpenMX .vps holds semilocal potentials V_l(r) … a new pseudopotential, not a relabelled file."}
```

!!! note "A refusal is an answer"
    It is not a gap to be filled later. See
    [Formats and conversions](formats.md).

### `GET /api/download/:id`

Serves the bytes. The id may contain a slash — a cached conversion lives at
`<source-id>/<name>` — and the core resolves it; the transport never builds a
path out of user input, and checks the result is inside the served tree before
opening it.

---

## Validate

### `POST /api/validate`

Multipart upload, field name `file`. Structural checks only — those need no
engine.

```json
{"valid": true, "errors": [], "warnings": []}
```

8 MB limit, enforced by both Nginx and the service. Nothing is stored.

Transferability is a different question and needs the atomic code: run
`pseudoforge validate` locally, or read [how validation
works](../how-to/validate.md).

---

## Generate

### `POST /api/generate` → `501`

```json
{
  "error": "generation_not_available_here",
  "message": "Generation runs on your machine, not on this server.",
  "instructions": "Install PseudoForge and run: pseudoforge generate -e <element> -t <family> -p <profile> -x <functional>",
  "install_url": "https://pseudo.amirkhani.me/docs/getting-started/installation/"
}
```

The public server is one core with no engines. Queueing a job no worker would
collect would look like it was working; refusing and saying what to run is the
honest answer. [The reasoning, and the queue-and-worker model as a possible
extension](../architecture/http.md#a-possible-extension-queue-and-worker).

---

## Errors

Every error has the same shape:

```json
{"error": "<machine_readable_code>", "message": "<a sentence for a human>"}
```

with extra fields where they help — `known` on an unknown engine or conversion,
`tool` on a missing converter, `reason` on a refusal.

| Status | When |
|---|---|
| `400` | the request is malformed, or asks for a path that does not exist |
| `404` | no such endpoint, engine, or file |
| `405` | the path exists, the method does not |
| `409` | refused, deliberately |
| `413` | the upload is over the limit |
| `429` | rate limited — 60 requests a minute per IP by default |
| `500` | something on the server failed |
| `501` | generation, which is not done here |
| `503` | a dependency this endpoint needs is not installed |

`405` rather than `404` on a wrong method is deliberate: it tells a client to
fix the verb rather than the URL.

---

## Rate limits

Two layers. Nginx limits at the edge (2 req/s, burst 10, `429`); the service
limits per IP (60 per minute by default). Both are configurable — see
[Deploy the website](../how-to/deploy.md).

## Versioning

The route table is the contract. A path will not change meaning; if an endpoint
needs a different shape it gets a different path. `GET /api/routes` returns the
current table, and `GET /api/version` the tool version.
