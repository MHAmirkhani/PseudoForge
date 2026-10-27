# Cutoff

`pseudoforge cutoff` reports verified plane-wave kinetic energy cutoffs (`ecutwfc` and `ecutrho`) for any element.

---

## Synopsis

```bash
pseudoforge cutoff -e <element> [--accuracy efficiency|precision] [--xc PBE|PBEsol] [-o <project-dir>] [--json]
```

### Arguments and options

| Argument / Flag | Description |
|---|---|
| `-e, --element <symbol>` | **Required.** Element symbol (e.g. `Fe`, `Si`, `Cu`). |
| `-a, --accuracy <level>` | Accuracy target: `efficiency` (standard, default) or `precision` (stringent). |
| `-x, --xc <functional>` | Functional parametrization: `PBE` (default) or `PBEsol`. |
| `-o, --project <dir>` | Optional project directory from a previous run to consult verified local cutoff scans. |
| `--json` | Emit structured result as JSON. |
| `-h, --help` | Show command usage. |

---

## Sources of Truth

Cutoff values are drawn systematically from three verified sources, without guessing:

1. **User project scans**: Measured convergence scans recorded in `tests/cutoffs.tsv` of completed projects (`-o <project-dir>`).
2. **SSSP verification tables**: Standard Solid State Pseudopotentials selection tables (SSSP v1.3.0), verified against all-electron reference datasets.
3. **PseudoDojo parameters**: Published ONCVPSP input configurations (`qcut`) from PseudoDojo v0.4.

If neither table nor scan covers the requested element and functional, the command exits with non-zero status (HTTP 404).

---

## HTTP API

```http
GET /api/cutoff?element=Fe&accuracy=precision&xc=PBE
```

Response (`200 OK`):

```json
{
  "element": "Fe",
  "accuracy": "precision",
  "xc": "PBE",
  "ecutwfc": 90,
  "ecutrho": 1080,
  "source": "SSSP precision",
  "library": "031PAW",
  "provenance": "SSSP v1.3.0 (Fe.pbe-spn-kjpaw_psl.0.2.1.UPF)"
}
```

---

## Web Interface

The web interface is available at `/cutoff/`, providing interactive element lookups, dual sliders for exploring cutoff and dual-ratio space, and copyable generation commands.
