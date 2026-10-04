# Convert between formats

```bash
pseudoforge convert --list              # every path and what it costs
pseudoforge convert in.van out.UPF      # formats inferred from the files
pseudoforge convert in.dat --to upf -o out.UPF
pseudoforge convert --why gth upf       # why is this one refused?
```

The complete matrix, generated from the code, is in
[Formats and conversions](../reference/formats.md). This page is about how to
use it and how to read a refusal.

## Three kinds of answer

**exact**
: Every number survives; a round trip returns the original. Most `→ upf`
  conversions are exact, performed by Quantum ESPRESSO's own `upfconv.x`.

**lossy**
: The conversion succeeds, and the target cannot hold everything the source
  had. What was dropped is named in a warning **and written into the
  provenance**, so it survives past the terminal session.

**refused**
: The target needs data the source does not contain. See below.

## Provenance travels with the file

Every conversion writes `<output>.provenance` beside its output:

```bash
pseudoforge convert Si.van Si.UPF
cat Si.UPF.provenance
```

```text
source=Si.van
source_format=van
target_format=upf
tool=upfconv.x
tool_version=7.6
kind=exact
```

Keep it. It is the answer to "where did this UPF come from", and for a `lossy`
conversion it is the record of what is no longer in the file.

## Refusals are answers, not gaps

Four paths are refused. Each one is refused because producing a file would mean
inventing the missing data and then labelling the result with the source's
name.

### `gth` → `upf`

> A GTH file is a dozen analytic coefficients, not a radial table. QE's own
> `upfconv.x` lists `.gth` as "DOES NOT WORK". Producing a UPF means sampling
> the analytic form onto a grid, which is a construction rather than a
> conversion.

CP2K, CPMD and ABINIT read GTH directly. If you need UPF for a GTH element,
generate a UPF with an engine that writes one.

### `vps` → `upf`

> An OpenMX `.vps` holds semilocal potentials $V_l(r)$, one curve per channel.
> UPF wants a separable Kleinman–Bylander form: projector functions and a
> $D_{ij}$ matrix. Going from one to the other means choosing a local channel
> and constructing projectors — a new pseudopotential, not a relabelled file.

Use ADPACK's output with OpenMX, or generate with an engine that writes UPF.

### `pawxml` → `upf`

> UPF has no tag for the kinetic-energy density. For a meta-GGA data set that
> term is what makes it meta-GGA, so the conversion would return an r2SCAN file
> that is no longer r2SCAN.

For LDA and GGA this conversion is unnecessary: AtomPAW writes UPF itself. See
[Tutorial 6](../tutorials/06-scan.md).

### Cross-family conversions

NC → US, US → PAW and their reverses are refused on principle. They are not
notations for the same object; they are different formalisms with different
data. There is no conversion to attempt.

!!! note "Why these will not be implemented"
    Not because the work is hard, but because what would be produced is a new
    pseudopotential wearing an old one's name — untested, unvalidated, and
    carrying a provenance that points at a file it is not derived from in any
    meaningful sense. The refusal *is* the correct behaviour.

## Choosing formats at generation time

Better than converting afterwards: ask the engine to write what you need.

```bash
pseudoforge generate -e Si -t nc -p sg15 --engine oncvpsp --format upf,psp8 -o ./out
```

Validated against the engine before anything runs:

```text
ERROR ONCVPSP (Hamann) cannot write 'recpot' (it writes: upf psp8 xml)
```

OPIUM is the broadest: UPF, FHI, CASTEP recpot, SIESTA psf, CPMD, CASINO,
CHAMP, Teter, QSO and NCPP from one generation.

## `psp8` is generated, not converted to

There is no conversion path to or from `psp8`, and this is a correction: the
`psp8 ↔ upf` and `fhi → psp8` paths were registered as **exact**, performed by
a program called `pspconvert` said to ship with ABINIT.

**`pspconvert` is not a program that exists.** What was checked:

| Checked | Found |
|---|---|
| ABINIT 8.10.3 and 9.10.3 source trees | no `pspconvert`; its `98_main` program list names no such file |
| conda-forge `abinit=8.10.2` and `abinit=10.0.3`, installed | no `pspconvert` in `bin/` |
| `abitk`, ABINIT 10's toolkit | header, k-point, crystal and band tools only; no pseudopotential subcommand |
| `upfconv.x -h` | lists `.upf`, `.vdb/.van`, `.rrkj3`, `.cpi/.fhi`, `.cpmd`; not psp8 |

The three paths are now **refused**, of kind `no-tool` — the conversion is
possible in principle and nothing performs it. That is a different answer from
the physics refusals, and `--why` says which you have hit:

```bash
pseudoforge convert --why upf psp8
```

The route that works is to generate it. ONCVPSP writes psp8 natively:

```bash
pseudoforge generate -e Si -t nc -x pbe --engine oncvpsp --format psp8 -o ./out
```

Asking for both gives you both — ONCVPSP's `psfile` takes `upf`, `psp8` or
`both`, and `--format upf,psp8` sets the third:

```bash
pseudoforge generate ... --format upf,psp8 -o ./out
# out/pseudos/Si.pbe-oncv.UPF
# out/pseudos/Si.pbe-oncv.psp8
```

To re-run the check on your own machine rather than take the above on trust:

```bash
tools/check-psp8-tools.sh              # look on PATH
tools/check-psp8-tools.sh /opt/abinit  # and in a specific prefix
```

It reports what it finds, exits 0 when some route to psp8 exists, and says so
plainly if a future ABINIT does ship a converter — in which case the three
refusals can become real paths again, with a test that runs them on a real file
first.

The result lands in `pseudos/` named like every other output — `Si.pbe-oncv.psp8`
— and is checked by `psp8_validate`, which reads the file's own header
(`pspcod`, `zatom`, `zion`, `lmax`, `mmax`, the projector counts) rather than
only its size. ABINIT reads it directly, with no intermediate step to lose
anything in.

## UPF v2 only — v1 is not produced

Both versions use the extension `.UPF` and are different formats: v1 is a
flat text layout, v2 is XML. PseudoForge writes **v2 only**.

`--upf 1` used to ask ld1.x for the legacy layout. The Quantum ESPRESSO in
this build (7.x) no longer recognises the `upf_v1_format` namelist key that
selected it, and no other engine here writes UPF v1. Rather than emit a v2
file under a v1 name, PseudoForge refuses the request:

```text
ERROR UPF v1 is not supported by the Quantum ESPRESSO in this build.
  QE 7.x's ld1.x no longer recognises the upf_v1_format namelist key, and
  no other engine here writes UPF v1.  Use --upf 2 (the default), or run
  an older QE (<= 6.x) if you need v1 for a legacy reader.
```

If you have an existing UPF v1 file it is still read: `pseudoforge validate`,
`pseudoforge import`, and `pseudoforge convert` all dispatch on the file's
own header (`lib/upf.sh::upf_format` reads `<UPF version=...>` for v2 and the
older layout for v1), so a v1 file produced elsewhere is usable here. What is
not available is *producing* a new one with the engines PseudoForge ships.

The version is recorded in the provenance either way, because the extension
does not say.
