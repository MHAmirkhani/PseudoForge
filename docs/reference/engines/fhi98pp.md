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

The fhi98PP beta is not included in PseudoForge. Obtain a copy from the authors and
unpack it. Set `FHI98PP_SRC_DIR` to the directory containing `src/fhipp.f`:

```bash
FHI98PP_SRC_DIR=/path/to/fhi98PP pseudoforge engines build fhi98pp
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
    fhi98PP's own `pslp.x` uses the CPI radial data and the saved
    all-electron reference. [ABINIT format 6](https://docs.abinit.org/developers/psp6_info/)
    requires a metadata header before the CPI radial records. Use the
    documented atomic, XC, local-channel and core-charge information.
    The example `examples/engine-pairs/evaluate_abinit.py` writes this
    header for the scalar Si/PW92 trial panel without a core-charge tail.

    If you need norm-conserving pseudopotentials *for Quantum ESPRESSO*, use
    [ONCVPSP](oncvpsp.md) or PSlibrary's NC set (`--engine ld1 -t nc`).

The registry lists `fhi → upf` and `cpi → upf` as **refused** (`no-tool`),
because QE 7.x's `upfconv.x` dropped the FHI reader from its dispatch.

## Validator

`generate --format cpi` saves the semilocal operator, all-electron reference
and analyzer input in the project. When atomic tests are enabled and
`pslp.x` is installed beside `fhipp.x`, PseudoForge runs it using the highest
constructed angular channel as local. Native output and log derivatives are
kept in the project's `tests/` directory. The reported verdict refers to this
choice of separable operator and the analyzer's energy range.

`pslp.x` output is parsed for ghost states. The first version of that check
searched for the word `ghost` — and matched the tool's own explanatory prose,
*"the ghost state analysis will assume a zero reference energy"*, reporting a
ghost in a clean pseudopotential. It now matches the actual finding line
(`^ *\* *ghost state`). A clean verdict requires a complete run and an
explicit no-ghost finding. Unfinished or indeterminate runs remain ungraded.

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

## Manual physics controls

Set explicit channel radii, pseudocore/NLCC or TM/Hamann construction; global scaling of implicit defaults is refused.

Use `pseudoforge physics fhi98pp` for the current catalogue and units.
[Prepare, edit and import native inputs](../../how-to/manual-generation.md)
for settings beyond that catalogue. Native solvers can reject physically or
numerically unsuitable values even when their syntax is valid.
