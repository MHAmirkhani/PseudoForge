# AtomPAW — Holzwarth

Natalie Holzwarth's PAW generator. The only engine here with a real meta-GGA
code path, and the second — with [`ld1`](ld1.md) — that produces PAW at all.

| | |
|---|---|
| **Families** | PAW |
| **Relativity** | non-relativistic, scalar — **non-relativistic only for meta-GGA** |
| **Functionals** | `LDA-PW`, `GGA-PBE`, `GGA-PBESOL`, `MGGA-R2SCAN-001`, `MGGA-R2SCAN-01`, plus libxc names when linked |
| **Native output** | UPF, ABINIT, PAW-XML — but see below for meta-GGA |
| **Licence** | GPL-3.0 |
| **Upstream** | <https://github.com/atompaw/atompaw> |

## Installing

```bash
pseudoforge engines build atompaw
```

Needs cmake, which PseudoForge fetches into its own prefix when the system one
is missing or too old. Links libxc when present.

## The meta-GGA path

This is why AtomPAW is here. Its r2SCAN is AtomPAW's own implementation
(`src/excor.F90`, `r2scanmod`), not libxc's; the two `MGGA-R2SCAN-*` keywords
differ only in the regularisation parameter η.

```bash
pseudoforge generate -e Si -t paw -p atompaw -x r2scan -r nonrel -o ./out
```

```text
functional=R2SCAN
functional.requested=r2scan
```

The two agree. Every other engine would record `functional=PBE` here and carry
the proxy note. See [Tutorial 6](../../tutorials/06-scan.md).

r2SCAN datasets are in the native store under
`atompaw/paw/r2scan/nonrel/pseudos/`, alongside every element the
ground-state configuration table covers. The store also carries
`pbe`, `pbesol` and `pw` for both scalar and non-relativistic runs.

### Constraint 1: non-relativistic only

AtomPAW's meta-GGA does not implement the relativistic solver. Asked for one,
it gets through the first SCF cycle and stops with
`for relativistic solver -- error stop`, which surfaces as
`no convergence in boundsr` — a message that explains nothing.

PseudoForge **refuses** the combination before anything runs:

```text
ERROR AtomPAW cannot generate meta-GGA with a relativistic solver.
  Its r2SCAN path is non-relativistic only.
  Re-run with -r nonrel, or choose a GGA functional to keep scalar relativity.
```

Refused rather than quietly switched: relativity is physics, and choosing
`nonrel` on your behalf would change the reference atom without saying so.

### Constraint 2: meta-GGA writes no UPF

A meta-GGA run produces PAW-XML and ABINIT, and no UPF. UPF has nowhere to
record the kinetic-energy density a meta-GGA functional needs, so AtomPAW
writes the two formats that can carry it and skips the third.

This is AtomPAW behaving correctly. The conversion `pawxml → upf` is
[refused](../formats.md) for the same reason: it would return an r2SCAN file
that is no longer r2SCAN.

!!! note "This once looked like a failure"
    An earlier version of PseudoForge treated the missing UPF as "wrote no PAW
    data set" and discarded a converged 733 KB r2SCAN dataset. The absence of a
    UPF is now understood and reported rather than treated as an error.

## Upstream defect: `type="LDA"` on meta-GGA output

AtomPAW writes the functional into its PAW-XML header as:

```xml
<xc_functional type="LDA" name="MGGA-R2SCAN-001"/>
```

The `type` attribute says LDA on a meta-GGA dataset. Only `name` is correct.

A consumer that reads `type` — the obvious thing to read, and what the
attribute is for — will treat an r2SCAN dataset as LDA and get wrong answers
silently.

**Read `name`, not `type`.** PseudoForge checks for this combination on every
AtomPAW output and warns, and the warning reaches `PROVENANCE.txt` so it
survives the file being copied elsewhere.

This is a defect in AtomPAW 4.2.0.6. It has **not** been reported upstream; if
you depend on it, report it or check whether a later release fixes it.

### Upstream defect: `type="LDA"` on meta-GGA output

AtomPAW writes the functional into its PAW-XML header as:

```xml
<xc_functional type="LDA" name="MGGA-R2SCAN-001"/>
```

The `type` attribute says LDA on a meta-GGA dataset. Only `name` is
correct. A consumer that reads `type` — the obvious thing to read, and what
the attribute is for — will treat an r2SCAN dataset as LDA and get wrong
answers silently.

**Read `name`, not `type`.** PseudoForge checks for this combination on
every AtomPAW output and warns, and the warning reaches the run's
`PROVENANCE.txt` so it survives the file being copied elsewhere.

This is a defect in AtomPAW 4.2.0.6. It has **not** been reported upstream
at the time of writing. A user who depends on this format should either
report it or check whether a later release fixes it.

## Input

AtomPAW's own line-oriented format:

```text
Si 14
MGGA-R2SCAN-001 nonrelativistic loggridv4 2001
3 3 0 0 0 0
3 0 2
...
```

Line 2 carries the functional keyword, the relativity keyword and the grid.

## Transferability

Reported as `atompaw leakage/overlap`: logarithmic-derivative agreement and
charge leakage outside the augmentation sphere. A real diagnostic, on a
different scale from `ld1 iswitch=2` — the method is always printed with the
result.

## Citation

> A. R. Tackett, N. A. W. Holzwarth and G. E. Matthews, "A Projector Augmented
> Wave (PAW) code for electronic structure calculations, Part I: atompaw for
> generating atom-centered functions", *Computer Physics Communications*
> **135**, 329–347 (2001).
> DOI [10.1016/S0010-4655(00)00244-7](https://doi.org/10.1016/S0010-4655(00)00244-7)

**AtomPAW's authors ask for no citation** — recorded as `no-request`, not as a
request. Checked 2026-09-27:

| where | what it says |
|---|---|
| the distribution | `README`, `README.md` and `AUTHORS` name N. A. W. Holzwarth (Wake Forest) and M. Torrent (CEA); nothing requests a reference |
| [Holzwarth's AtomPAW page](https://users.wfu.edu/natalie/papers/pwpaw/man.html) | no request; names the meta-GGA paper, PRB **105**, 125144 (2022) |
| [ABINIT's AtomPAW page](https://www.abinit.org/atomic_data/paw/tools/atompaw/atompawgenerator-ABINIT.html), which hosts it now | no request; lists the paper above as reference [1] |

That paper is the code's own, so it is the one to use. If you generated
**meta-GGA** data sets — the reason to reach for AtomPAW here — the 2022 paper
describes that implementation and is worth citing alongside it.

---

## On the API

This engine as the server reports it, including whether its binary is
present there:

```bash
curl -s https://pseudo.amirkhani.me/api/engines/atompaw
pseudoforge api GET /api/engines/atompaw          # the same thing, locally
```

See the [HTTP API reference](../http-api.md). On the public server
`available` is `false` for every engine -- it does not have them, and
[that is the architecture](../../architecture/http.md).

## See also

- [Coverage](../coverage.md) — which elements AtomPAW covers, per family
- [Limitations](../limitations.md#atompaw-diracrelativistic-incomplete) — the meta-GGA constraints, in one place
- [Upstream](../upstream.md#atompaw-typelda-on-meta-gga-output) — the `type="LDA"` defect, and why it is not filed
- [The native store](../store.md) — the r2SCAN PAW datasets shipped with PseudoForge
