# Build Command

`pseudoforge build-command` turns high-level physics choices into an exact, validated CLI invocation for pseudopotential generation.

---

## Synopsis

```bash
pseudoforge build-command -e <element> [options]
```

### Arguments and options

| Argument / Flag | Description |
|---|---|
| `-e, --element <symbol>` | **Required.** Element symbol or range (e.g. `Fe`, `Si`, `1-36`). |
| `-t, --family <family>` | Pseudopotential family: `paw`, `nc`, or `us`. |
| `-x, --xc <functional>` | Exchange-correlation functional (e.g. `pbe`, `pbesol`, `pz`, `scan`). |
| `-r, --relativity <rel>` | Relativistic treatment: `scalar`, `full`, or `nonrel`. |
| `--engine <engine>` | Specific generator engine (e.g. `oncvpsp`, `atompaw`, `ld1`, `opium`, `ape`). |
| `-p, --profile <name>` | Recipe profile to draw from (e.g. `psl-high`, `pseudodojo`, `sg15`). |
| `-f, --format <format>` | Output format (e.g. `upf`, `psp8`, `psml`, `gth`, `vps`). |
| `--ecut <Ry>` | Wavefunction cutoff hint to embed. |
| `--dual <ratio>` | Charge density dual ratio (`ecutrho / ecutwfc`). |
| `--json` | Emit result as structured JSON object. |
| `-h, --help` | Show command usage. |

---

## Physics Validation and Refusal

`pseudoforge build-command` evaluates the assembled specification with the engine registry and `cli_check_spec`. If incompatible choices are provided (for example, requesting PAW from ONCVPSP, or full relativity from an engine that does not support spin-orbit coupling), the tool refuses with an exact diagnostic message and non-zero exit status (HTTP 409).

---

## HTTP API

```http
GET /api/build-command?element=Fe&family=paw&xc=pbe&engine=atompaw&relativity=full
```

Response (`200 OK`):

```json
{
  "command": "pseudoforge generate -e Fe --engine atompaw -t paw -p psl-high -r full --source local -x pbe -j 4",
  "explanation": "Exact CLI invocation constructed from validated physics choices."
}
```

Incompatible choices response (`409 Conflict`):

```json
{
  "error": "refused",
  "reason": "ONCVPSP (Hamann) cannot make paw pseudopotentials (it does: nc)"
}
```

---

## Interactive Components

The command builder is embedded interactively across the web frontend:
- On `/advise/`, tuning recommendations live.
- On `/cutoff/`, adapting the generation command to dual slider cutoffs.
- On the homepage (`/`), providing the exact command under the generator form.
