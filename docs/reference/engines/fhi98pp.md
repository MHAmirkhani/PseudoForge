# fhi98PP — Fuchs / Scheffler

The FHI98 norm-conserving construction, with its own ghost-state and
transferability analysis tool.

| | |
|---|---|
| **Families** | NC |
| **Relativity** | scalar |
| **Functionals** | LDA, GGA |
| **Native output** | `.cpi` / `.fhi` — **no UPF**, and see the dead end below |
| **Licence** | see the licence inside the distribution |
| **Upstream** | <https://th.fhi-berlin.mpg.de/th/fhi98md/fhi98PP/> |

## Installing

```bash
pseudoforge engines build fhi98pp
```

## Parameters

PseudoForge uses fhi98PP's own vendor database — `bin/Elements/{Ham,TM}/`, the
FHI element sets — whose own README says *"do not use uncritically"*. Files
generated from it are labelled `vendor` in the provenance, not `library`.

## The UPF dead end

fhi98PP generates fine. **Converting its output to UPF does not work on
Quantum ESPRESSO 7.x**, and that is upstream's doing rather than
PseudoForge's.

QE's `upflib/read_ps.f90` dispatches on file extension and has branches for
`.psml`, `.vdb`/`.van`, `.RRKJ3` and `.gth`; everything else falls through to
`read_ncpp`, which cannot read an FHI file. `read_fhi` is still compiled into
`upfconv.x` and still advertised in its `-h` output, but nothing calls it.

The known-good sample shipped in `fhi98PP/sample/al:h.cpi` fails in exactly the
same way, which is how this was confirmed — so renaming extensions will not
help.

PseudoForge therefore keeps the `.cpi` under `pseudos/native/` and says plainly
why there is no UPF.

!!! note "The file is still useful"
    ABINIT reads `.cpi` directly, and fhi98PP's own `pslp.x` does genuine
    ghost-state and transferability analysis on it.

    If you need norm-conserving pseudopotentials *for Quantum ESPRESSO*, use
    [ONCVPSP](oncvpsp.md) or PSlibrary's NC set (`--engine ld1 -t nc`).

The registry lists `fhi → upf` and `cpi → upf` as **refused** (`no-tool`),
because QE 7.x's `upfconv.x` dropped the FHI reader from its dispatch.

## Validator

`pslp.x` output is parsed for ghost states. The first version of that check
searched for the word `ghost` — and matched the tool's own explanatory prose,
*"the ghost state analysis will assume a zero reference energy"*, reporting a
ghost in a clean pseudopotential. It now matches the actual finding line
(`^ *\* *ghost state`).

A validator that rejects valid output is worse than no validator. See
[Adding an engine](../../contributing/adding-an-engine.md).

## Citation

> M. Fuchs and M. Scheffler, "Ab initio pseudopotentials for electronic
> structure calculations of poly-atomic systems using density-functional
> theory", *Computer Physics Communications* **119**, 67–98 (1999).
> DOI: [10.1016/S0010-4655(98)00201-X](https://doi.org/10.1016/S0010-4655(98)00201-X)

---

## On the API

This engine as the server reports it, including whether its binary is
present there:

```bash
curl -s https://pseudo.amirkhani.me/api/engines/fhi98pp
pseudoforge api GET /api/engines/fhi98pp          # the same thing, locally
```

See the [HTTP API reference](../http-api.md). On the public server
`available` is `false` for every engine -- it does not have them, and
[that is the architecture](../../architecture/http.md).

## See also

- [Coverage](../coverage.md) — which elements fhi98PP covers
- [Limitations](../limitations.md#conversions-that-do-not-exist) — why `fhi → upf` is not a conversion
- [The native store](../store.md) — the `.cpi` files shipped with PseudoForge
