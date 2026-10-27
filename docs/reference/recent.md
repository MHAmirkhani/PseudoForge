# Recently Added Files

`pseudoforge recent` displays the most recently added pseudopotential files in the PseudoForge store, newest first.

---

## Synopsis

```bash
pseudoforge recent [--count <N>] [--json]
```

### Arguments and options

| Argument / Flag | Description |
|---|---|
| `--count, -n <N>` | Number of files to report (default: 10). A bare integer argument (e.g. `pseudoforge recent 20`) is also accepted. |
| `--json` | Emit structured JSON array of recent file records. |
| `-h, --help` | Show command usage. |

---

## Output Fields

Each row reports:

- **Date**: ISO date (`YYYY-MM-DD`) when the file was generated and added.
- **Filename**: basename of the file.
- **Profile**: library profile name.
- **Family**: `NC`, `PAW`, or `US`.
- **Functional**: exchange-correlation parametrization (e.g. `PBE`, `PBESOL`, `SCAN`).

---

## HTTP API

```http
GET /api/recent?count=10
```

Returns `200 OK` with JSON array of objects containing `date`, `filename`, `element`, `xc`, `family`, `profile`, `id`, and `path`.
