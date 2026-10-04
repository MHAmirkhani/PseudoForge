# Choose an engine

Most of the time you should not. Asking for PAW from PSlibrary implies
`ld1.x`; asking for SG15 implies ONCVPSP; the profile and the family between
them pick the engine that library was actually built with, and overriding that
means generating something else and calling it by the library's name.

`--engine` exists for when you are not reproducing a library.

## Decide by what you need

**A PAW or ultrasoft dataset for Quantum ESPRESSO**
: [`ld1`](../reference/engines/ld1.md). It is QE's own atomic code, it produces
  PSlibrary, and it is the only engine here that does all three families.

**Hard, accurate norm-conserving — for GW, BSE, TDDFT, EPW**
: [`oncvpsp`](../reference/engines/oncvpsp.md). Hamann's optimised
  construction, unusually soft for norm-conserving. This is what SG15 and
  PseudoDojo are built with.

**A meta-GGA dataset generated self-consistently**
: [`atompaw`](../reference/engines/atompaw.md), and only AtomPAW. The other
  eight have no meta-GGA code path. Note the constraints: non-relativistic
  only, and the output is PAW-XML rather than UPF. See
  [Tutorial 6](../tutorials/06-scan.md).

**A functional nothing else supports**
: [`ape`](../reference/engines/ape.md), which is backed by libxc and therefore
  covers a far wider range than the engines with built-in functional tables.

**GTH/HGH analytic coefficients for CP2K or CPMD**
: [`gth`](../reference/engines/gth.md). These are a dozen analytic parameters
  rather than a radial table, which is also why they cannot be converted to
  UPF.

**OpenMX**
: [`adpack`](../reference/engines/adpack.md), which writes `.vps` and `.pao`.

**Many output formats from one generation**
: [`opium`](../reference/engines/opium.md) writes UPF for every element it
  covers; FHI, CASTEP recpot, SIESTA psf, CPMD, CASINO, CHAMP, QSO and NCPP
  as well, for scalar/non-relativistic runs; and Teter for fully-relativistic
  runs. PseudoForge patches an upstream OPIUM 4.1.0 bug that otherwise makes
  the non-UPF writers crash on any element with a gap in its l-shells
  (Fe, Cu, Zn, Au, ...); see the engine page for details.

**Ultrasoft in Vanderbilt's original code**
: [`uspp`](../reference/engines/uspp.md), for reproducing older work or the
  classic Vanderbilt tables specifically.

**The FHI98 construction**
: [`fhi98pp`](../reference/engines/fhi98pp.md).

## Decide by what you have

```bash
pseudoforge engines list
```

```text
  ok        Quantum ESPRESSO ld1.x     /opt/espresso/7.6/ld1.x
  ok        ONCVPSP (Hamann)           ~/.pseudoforge/engines/bin/oncvpsp.x
  missing   APE                        -> pseudoforge engines build ape
```

An engine you do not have is not a silent fallback. Asking for it fails with
the command that would install it.

## What each can produce

| Engine | NC | US | PAW | Writes UPF | Full-rel |
|---|:-:|:-:|:-:|:-:|:-:|
| `ld1` | ● | ● | ● | yes | yes |
| `oncvpsp` | ● | | | yes | yes |
| `uspp` | | ● | | no | — |
| `fhi98pp` | ● | | | no | — |
| `opium` | ● | | | yes | — |
| `gth` | ● | | | no | — |
| `atompaw` | | | ● | yes* | — |
| `ape` | ● | | | yes | — |
| `adpack` | ● | | | no | — |

\* AtomPAW writes UPF for LDA and GGA, and PAW-XML for meta-GGA — see
[Tutorial 6](../tutorials/06-scan.md).

The authoritative version of this table, generated from the registry, is on the
[Engines reference page](../reference/engines.md). If the two ever disagree,
believe that one.

## "Writes UPF" matters more than it looks

An engine that does not write UPF produces its own format, and getting to UPF
means a conversion — which appears in the provenance, and which may be `exact`,
`lossy`, or **refused**.

For USPP and fhi98PP the conversion to UPF is exact, done by QE's own
`upfconv.x`, and costs you nothing but a line in the provenance.

For GTH and ADPACK it is **refused**. Those engines' outputs are meant for CP2K
and OpenMX respectively, which read them natively. If you need UPF, you need a
different engine, and PseudoForge will say so rather than producing a file that
misrepresents itself. See [Formats](../reference/formats.md).

## Overriding, and what it means

```bash
pseudoforge generate -e Si -t nc -p sg15 --engine oncvpsp -o ./out
```

Explicit and redundant — `sg15` implies `oncvpsp` anyway. Harmless, and it
documents intent.

```bash
pseudoforge generate -e Si -t nc -p psl-high --engine opium -o ./out
```

This is a different thing: taking PSlibrary's *parameters* and generating with
OPIUM's construction. The result is **not** a PSlibrary pseudopotential, and
PseudoForge tags it so it cannot be mistaken for one. That is a legitimate
experiment; just do not report it as PSlibrary.

```bash
pseudoforge generate -e Si -t us --engine oncvpsp
```

```text
ERROR ONCVPSP (Hamann) cannot make us pseudopotentials (it does: nc)
```

Checked before anything runs.

## If you genuinely do not know

Use the default. `psl-high` with `ld1` is a good answer for most solid-state
work, it is a published library rather than a guess, and it comes with
transferability test decks so you get a grade instead of a shrug.

Then, if the result is too hard for your cutoff, try `psl-low`; if you need
norm-conserving, try `sg15`; and compare:

```bash
pseudoforge compare ./a/pseudos/Si.*.UPF ./b/pseudos/Si.*.UPF
```
