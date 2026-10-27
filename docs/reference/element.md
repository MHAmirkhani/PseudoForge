# Element Summary

`pseudoforge element` inspects everything available in the PseudoForge store for a specific element, grouped by pseudopotential family and functional, and lists any missing profiles with exact generation commands.

---

## Synopsis

```bash
pseudoforge element <symbol> [--json]
```

### Arguments and options

| Argument / Flag | Description |
|---|---|
| `<symbol>` | **Required.** Element symbol, name, or atomic number (e.g. `Si`, `Iron`, `26`). |
| `--json` | Emit structured JSON list of files and missing profiles. |
| `-h, --help` | Show command usage. |

---

## Output Structure

The output groups available native files by formalism:

1. **Norm-conserving (`NC`)**: files, functionals, relativistic treatment, generator engines, and sizes.
2. **Projector augmented-wave (`PAW`)**: datasets, functionals, and generator codes.
3. **Ultrasoft (`US`)**: pseudopotentials with relativistic tags and sizes.
4. **Not available in store**: profiles that can generate this element locally but are not pre-cached in the store, complete with the recommended `pseudoforge generate` invocation.

---

## HTTP API

```http
GET /api/elements/:symbol
```

Returns `200 OK` with JSON describing the element, available files, and unbuilt profiles.
