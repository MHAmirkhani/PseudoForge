# Compare

`pseudoforge compare` inspects and diffs two pseudopotentials across physics, generators, cutoff recommendations, and structural representations.

---

## Synopsis

```bash
pseudoforge compare <a> <b> [--ecut N] [--diff] [--json]
```

### Arguments and options

| Argument / Flag | Description |
|---|---|
| `<a>` | **Required.** First pseudopotential file path or native store ID. |
| `<b>` | **Required.** Second pseudopotential file path or native store ID. |
| `--ecut N` | Plane-wave kinetic energy cutoff (Ry) to probe when running Quantum ESPRESSO numerical comparison. |
| `--diff, --meta` | Perform metadata, cutoff, and structural diff without invoking `pw.x`. |
| `--json` | Emit structured comparison object as JSON on stdout. |
| `-h, --help` | Show command usage. |

---

## Output Fields

When run in metadata comparison mode, `pseudoforge compare` reports:

- **Metadata summary**: Element, Engine, Exchange-Correlation functional, Family (NC, PAW, US), Relativity, Format, Size, and SSSP precision cutoff.
- **Diff summary**:
  - `size_bytes_delta`: Difference in file size in bytes ($B - A$).
  - `sha256_equal`: Whether the files are cryptographically identical.
  - `engine_changed`, `family_changed`, `xc_changed`, `relativity_changed`, `format_changed`: Flags indicating dimension shifts.
- **Physics warnings**: Cautions regarding projector indexing, exchange-correlation mismatch, and transferability differences.

---

## HTTP API

```http
POST /api/compare
```

Request body:

```json
{
  "a": "Fe.pbe-sp-van_ak.UPF",
  "b": "Fe.pbe-spn-kjpaw_psl.1.0.0.UPF"
}
```

Response (`200 OK`):

```json
{
  "a": { "id": "Fe.pbe-sp-van_ak.UPF", "element": "Fe", "engine": "oncvpsp", "xc": "PBE", "cutoffs": { "sssp_precision": 75 } },
  "b": { "id": "Fe.pbe-spn-kjpaw_psl.1.0.0.UPF", "element": "Fe", "engine": "atompaw", "xc": "PBE", "cutoffs": { "sssp_precision": 80 } },
  "diff": {
    "size_bytes_delta": -1420,
    "sha256_equal": false,
    "family_changed": false,
    "xc_changed": false,
    "relativity_changed": false,
    "engine_changed": true,
    "format_changed": false
  },
  "warnings": [
    "Switching engine between oncvpsp and atompaw may change projector indexing."
  ]
}
```

---

## Web Interface

The web interface is accessible at `/compare/`, providing autocomplete selectors, side-by-side property inspection, and radial plot overlays using `upf-plot.js`.
