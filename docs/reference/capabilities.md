# Capabilities

`pseudoforge capabilities` displays the honest capability matrix across the three PseudoForge deployment tiers.

---

## Synopsis

```bash
pseudoforge capabilities [--json]
```

### Arguments and options

| Argument / Flag | Description |
|---|---|
| `--json` | Emit structured JSON describing the capabilities and status of each tier. |
| `-h, --help` | Show command usage. |

---

## Deployment Tiers

PseudoForge separates operations that can be performed over HTTP from those that require local engines on your machine:

### 1. Store alone (Website / HTTP API)

- ✅ Browse and download pre-built files
- ✅ Validate an existing pseudopotential file
- ✅ Convert formats on demand (`upfconv.x`)
- ✅ Read provenance, checksums, and academic citations
- ❌ Generate custom pseudopotentials
- ❌ Run cutoff convergence scans (`pw.x`)
- ❌ Run transferability ghost-state tests
- ❌ Auto-fix failed generations

### 2. PseudoForge CLI without engines

- ✅ All capabilities of the store
- ✅ Inspect and adapt recipe decks (`pseudoforge recipe <element>`)
- ✅ Command-line validation and analysis
- ❌ Generate custom pseudopotentials (requires generator engines)

### 3. PseudoForge CLI with engines installed

- ✅ All of the above
- ✅ Generate custom pseudopotentials across 9 engines
- ✅ Run cutoff scans with `pw.x`
- ✅ Run logarithmic derivative and ghost-state transferability tests
- ✅ Automatic error recovery and tuning
- ✅ User-defined recipes and parameter overrides

---

## HTTP API

```http
GET /api/capabilities
```

Returns `200 OK` with JSON detailing the supported and unsupported capabilities of each tier.
