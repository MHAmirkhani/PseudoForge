# Formats and conversions

Two questions, and they are different: **what can an engine write**, and **what
can be turned into what afterwards**.

The tables are generated from `data/formats.tsv` and the conversion registry in
`lib/convert.sh`, so a path added to the code appears here without anyone
remembering to add it.

<!-- generated:begin -->
<!-- Do not edit between these markers: tools/gen_reference.sh writes them. -->

### Formats

| id | Format | Written natively by | Extension |
|---|---|---|---|
| `upf` | UPF (Quantum ESPRESSO v2) | ld1 oncvpsp uspp opium atompaw ape | `.UPF` |
| `psp8` | psp8 (ABINIT) | oncvpsp | `.psp8` |
| `fhi` | FHI / abinit | opium | `.fhi` |
| `recpot` | CASTEP recpot | opium | `.recpot` |
| `siesta` | SIESTA psf | opium | `.psf` |
| `cpmd` | CPMD | opium | `.cpmd` |
| `casino` | CASINO | opium | `.casino` |
| `champ` | CHAMP | opium | `.champ` |
| `teter` | Teter | opium | `.teter` |
| `qso` | QSO / Qbox XML | opium | `.xml` |
| `ncpp` | NCPP | opium | `.ncpp` |
| `xml` | UPF XML schema | ld1 oncvpsp uspp fhi98pp opium | `.xml` |
| `cpi` | cpi (FHI/abinit) | fhi98pp | `.cpi` |
| `uspp` | Vanderbilt .uspp | uspp | `.uspp` |
| `van` | Vanderbilt .van (ASCII) | uspp | `.van` |
| `gth` | GTH coefficients (CP2K) | gth | `.gth` |
| `gth-cpmd` | GTH coefficients (CPMD) | gth | `.cpmd` |
| `gth-abinit` | GTH coefficients (ABINIT) | gth | `.abinit` |
| `paw-abinit` | PAW dataset (ABINIT) | atompaw | `.abinit` |
| `paw-xml` | PAW-XML schema | atompaw | `.xml` |
| `openmx` | OpenMX .vps | adpack | `.vps` |
| `openmx-pao` | OpenMX pseudo-atomic orbitals | adpack | `.pao` |

### Conversions

Every path PseudoForge knows about, and what it costs. A **refused**
path is a deliberate answer, not a gap -- the reason is given below.

The **demonstrated** column is a measurement, not a promise: it says
whether that exact path has been run against a real file on a real
machine. A path can be registered, have its tool installed, and still
not work.

| From | To | Kind | Tool | Demonstrated |
|---|---|---|---|---|
| `van` | `upf` | **exact** | upfconv | yes |
| `vdb` | `upf` | **exact** | upfconv | yes |
| `rrkj3` | `upf` | **exact** | upfconv | yes |
| `upf` | `xml` | **exact** | upfconv | yes |
| `pawxml` | `upf` | **refused** | none | n/a |
| `vps` | `upf` | **refused** | none | n/a |
| `gth` | `upf` | **refused** | none | n/a |
| `psp8` | `upf` | **refused** | none | n/a |
| `upf` | `psp8` | **refused** | none | n/a |
| `fhi` | `psp8` | **refused** | none | n/a |
| `cpi` | `upf` | **refused** | none | n/a |
| `fhi` | `upf` | **refused** | none | n/a |
| `cpmd` | `upf` | **refused** | none | n/a |

### Why the refusals are refusals

**`pawxml` to `upf`** (physics)

> UPF has no tag for the kinetic-energy density. For a meta-GGA data set that term is what makes it meta-GGA, so the conversion would return an r2SCAN file that is no longer r2SCAN. For LDA and GGA the conversion is unnecessary: AtomPAW writes UPF itself -- add PWSCFOUT to the deck, or run without --format pawxml.

**`vps` to `upf`** (physics)

> An OpenMX .vps holds semilocal potentials V_l(r), one curve per channel. UPF wants a separable Kleinman-Bylander form: projector functions and a D_ij matrix. Going from one to the other means choosing a local channel and constructing projectors -- a new pseudopotential, not a relabelled file. Use ADPACK's output with OpenMX, or generate with an engine that writes UPF.

**`gth` to `upf`** (physics)

> A GTH file is a dozen analytic coefficients, not a radial table. QE's own upfconv.x lists .gth as "DOES NOT WORK". Producing a UPF means sampling the analytic form onto a grid, which is a construction rather than a conversion. CP2K, CPMD and ABINIT read GTH directly.

**`psp8` to `upf`** (no-tool)

> No tool performs this conversion. ABINIT ships no psp8 converter (checked: the 8.10.3 and 9.10.3 source trees, and the conda-forge binaries of 8.10.2 and 10.0.3), and QE's upfconv.x does not list psp8 among the formats it reads. The two layouts both tabulate Kleinman-Bylander projectors, so a converter is possible to write; none exists, and PseudoForge does not invent one. To get a UPF, generate one: every engine here except GTH and ADPACK writes UPF directly.

**`upf` to `psp8`** (no-tool)

> No tool performs this conversion -- see psp8 -> upf for what was checked. psp8 does not need converting to: ONCVPSP writes it natively. Run with --engine oncvpsp --format psp8 and the file ABINIT reads is the file the engine produced, with no intermediate step to lose anything in.

**`fhi` to `psp8`** (no-tool)

> No tool performs this conversion -- see psp8 -> upf for what was checked. ABINIT appears to read the fhi layout directly (its binary carries an m_psp6 module, and pspcod 6 is the fhi98PP format -- Unverified: check ABINIT's psp6 reader in the source). For psp8 specifically, generate it: --engine oncvpsp --format psp8.

**`cpi` to `upf`** (no-tool)

> No tool performs this in Quantum ESPRESSO 7.x. upfconv.x's help lists .cpi and .fhi, but its reader dispatch (read_ps_new in upflib/read_ps.f90) has no FHI branch: the file falls through to the old PWSCF reader and fails. QE 7.6 ships no fhi2upf.x. ABINIT reads the FHI layout directly; for a UPF, generate one with an engine that writes UPF.

**`fhi` to `upf`** (no-tool)

> No tool performs this in Quantum ESPRESSO 7.x. upfconv.x's help lists .cpi and .fhi, but its reader dispatch (read_ps_new in upflib/read_ps.f90) has no FHI branch: the file falls through to the old PWSCF reader and fails. QE 7.6 ships no fhi2upf.x. ABINIT reads the FHI layout directly; for a UPF, generate one with an engine that writes UPF.

**`cpmd` to `upf`** (no-tool)

> No tool performs this in Quantum ESPRESSO 7.x. upfconv.x's help lists .cpmd, but its reader dispatch (read_ps_new in upflib/read_ps.f90) has no CPMD branch, and QE 7.6 ships no cpmd2upf.x. CPMD reads the file directly; for a UPF, generate one -- OPIUM writes both from one run (--engine opium --format upf,cpmd).

<!-- generated:end -->

---

## How to read the "kind" column

**exact**
: Every number survives. A round trip returns the original file. The conversion
  is a change of notation, not of content.

**lossy**
: The conversion succeeds but the target cannot hold everything the source
  had. What is dropped is named in a warning, and that warning is written into
  `PROVENANCE.txt` so it survives past the terminal session that produced it.

**refused**
: The target needs data the source does not contain. Producing a file anyway
  would mean constructing the missing part and labelling the result with the
  source's name. The refusal is the correct answer, and the reason is given
  rather than a generic error.

!!! note "A refusal is not a missing feature"
    Each refused path above has a reason that is about the physics, not about
    unfinished work. Implementing them is not on the roadmap, because what
    would be implemented is a new pseudopotential wearing an old one's name.

## Converting

```bash
pseudoforge convert --list                       # every path, with its kind
pseudoforge convert in.van out.UPF               # infer both formats
pseudoforge convert in.van --to upf -o out.UPF   # or state the target
pseudoforge convert --why gth upf                # why is this refused?
```

Every conversion writes `<output>.provenance` next to the output, recording the
source file, the tool, the tool's version, and the kind:

```text
source=Si.van
source_format=van
target_format=upf
tool=upfconv.x
tool_version=7.6
kind=exact
```

A `lossy` conversion additionally records what was lost. See [Convert between
formats](../how-to/convert-formats.md) for the workflow.

## Choosing output formats at generation time

`--format` takes a comma-separated list, validated against the engine that will
actually run:

```bash
pseudoforge generate -e Si -t nc -p sg15 --engine oncvpsp --format upf,psp8
```

A format the chosen engine cannot produce is refused before anything runs,
rather than producing a UPF named `.psp8`:

```text
ERROR ONCVPSP (Hamann) cannot write 'recpot' (it writes: upf psp8 xml)
```

## A note on `.UPF` as a name

Both UPF v1 and UPF v2 use the extension `.UPF`. They are different formats:
v1 is a flat text layout, v2 is XML. PseudoForge writes **v2 only** — v1 is
read (for files produced elsewhere) but not produced. QE 7.x's ld1.x no
longer recognises the `upf_v1_format` key that selected v1, so `--upf 1` is
refused rather than allowed to emit a v2 file under a v1 name. The version
recorded in a file's header is what the reader dispatches on, not the
extension, because the extension does not say.

---

## On the API

The same two tables, as JSON:

```bash
curl -s https://pseudo.amirkhani.me/api/formats | jq .conversions
pseudoforge api GET /api/formats
```

A conversion requested through [`POST /api/convert`](http-api.md)
returns `409` with the refusal's reason where the path is refused,
and `503` where the converter is simply not installed on that server --
two different answers that a single error code would have flattened
into one.
