# Format conversion

`pseudoforge convert <file> --to <format>`

The boundary this module keeps is the difference between **transforming a
file** and **making a different pseudopotential**. They look alike from the
command line and are not alike at all: the second produces a file that passes
every structural check and is the wrong physics.

A conversion is in scope when every number the target needs is already in the
source, and the work is rearranging and relabelling. It is out of scope when
the target needs something the source does not contain — then the only way to
produce it is to construct it, and a construction issued under the original
library's name is what this tool refuses to do.

Run `pseudoforge convert --list` for the current table, and
`pseudoforge convert --why <from> <to>` for any refusal.

## Paths

| from | to | kind | proof |
|---|---|---|---|
| van, vdb | UPF | exact | pw.x: −15.90704670 Ry from the `.van` and from the UPF |
| rrkj3 | UPF | exact | pw.x: −22.99954954 Ry from the `.RRKJ3` and from the UPF |
| UPF | xml | exact | pw.x: −15.76231144 Ry from both |
| cpi, fhi | UPF | **refused** (no-tool) | QE 7.x has no FHI reader in `upfconv.x` |
| cpmd | UPF | **refused** (no-tool) | QE 7.x has no CPMD reader in `upfconv.x` |
| PAW-XML | UPF | **refused** (physics) | — |
| OpenMX `.vps` | UPF | **refused** (physics) | — |
| GTH | UPF | **refused** (physics) | — |
| psp8 | UPF | **refused** (no-tool) | — |
| UPF | psp8 | **refused** (no-tool) | — |
| fhi | psp8 | **refused** (no-tool) | — |

Bulk Si, 30/240 Ry, 4×4×4, `conv_thr` 1e-10. Each exact path is checked by
letting `pw.x` read the *source* format itself — it reads `.van`, `.RRKJ3`
and QE-XML natively — and comparing with the converted file. Identical to the
last printed digit, pressures included. `PF_SLOW_TESTS=1 tests/test_convert.sh`
re-runs all three.

## Two kinds of refusal, kept apart

A refusal answers one of two different questions, and blurring them throws away
the only part the reader can act on.

**physics** — the target format needs numbers the source does not contain.
No tool could do it without inventing them, so no tool ever will. PAW-XML,
`.vps` and GTH are here.

**no-tool** — the conversion is arithmetically possible and nothing performs
it. The three `psp8` paths are here, and they used to be something worse: they
were registered as **exact**, performed by ABINIT's `pspconvert`.

There is no such program. It is absent from the ABINIT 8.10.3 and 9.10.3
source trees and from the conda-forge binaries of 8.10.2 and 10.0.3; `abitk`,
ABINIT 10's toolkit, has no pseudopotential subcommand at all; and QE's
`upfconv.x -h` lists the formats it reads, psp8 not among them. The registry
had promised a path that could never run, and the report's `AVAILABLE: no`
column read as one install away.

psp8 does not need a converter. **ONCVPSP writes it natively**
(`--format psp8`), and the file ABINIT reads is then the file the engine
produced.

## Validation checks form, not physics

Until every exact path was run through `pw.x`, "demonstrated" meant *the
converted file passes UPF validation*. Three things turned up once the physics
was checked instead:

**`van → upf` produced a file pw.x could not open.** upfconv.x writes the
`PP_QFCOEF` block as one 2,496-character row; QE's own XML reader stops at
1024 (`maxline=1024` in `upflib/xmltools.f90`) with *xmlr_opentag: severe
error, line too long*. A normaliser that re-wraps such rows already existed —
but only on the `generate` path, so `pseudoforge convert` and the website's
`/api/convert` handed the broken file out. It lives in `lib/upf.sh` now and
both paths call it, and the validator enforces QE's 1024-character limit.

**`rrkj3 → upf` failed outright.** `upfconv -h` advertises "*.rrkj3 or
*.RRKJ3", but its dispatch compares the tail of the name with no case
folding and matches only `.RRKJ3`. The converter stages the file under that
spelling. The result had `xmin="-Infinity"` in `PP_MESH` — RRKJ3 does not
record where its mesh starts, so the value is undefined — and the undefined
attributes are removed rather than filled with a guess.

**`cpi`, `fhi` and `cpmd → upf` cannot be done by QE 7.x at all.** Its help
lists them; its code does not read them. `upfconv.f90` sends every file
through `read_ps_new` (`upflib/read_ps.f90`), whose dispatch is:

```text
.psml -> read_psml   .vdb/.van -> readvan   .RRKJ3 -> readrrkj
.gth  -> error       anything else -> read_ncpp   (old PWSCF format)
```

No FHI branch, no CPMD branch, and QE 7.6 ships no `fhi2upf.x` or
`cpmd2upf.x`. These are `no-tool` refusals, and the real files that show it —
fhi98PP's `.cpi`, OPIUM's `.cpmd` — are kept in `tests/fixtures/`, because a
refusal nobody can reproduce is a rumour.

One caution concerns the RRKJ3 *format* rather than the conversion. The
RRKJ3 that ld1.x writes from a modern PSlibrary deck is already **2.2 eV per
Si cell** away from the UPF ld1.x writes from the same deck: the old layout
has no l-resolved augmentation. The conversion reproduces the RRKJ3 exactly;
it cannot restore what the RRKJ3 never held.

## Why the physics refusals are refusals

These are not missing features. Each was investigated and found not to be a
format conversion.

### PAW-XML → UPF

**UPF has no tag for the kinetic-energy density.** A real PAW UPF contains
`PP_AEWFC`, `PP_AE_NLCC`, `PP_AE_VLOC`, `PP_AUGMENTATION`, `PP_BETA`,
`PP_DIJ`, `PP_FULL_WFC`, `PP_MULTIPOLES`, `PP_PAW`, `PP_QIJL` and the rest —
and nothing that can hold τ.

For a meta-GGA data set that term **is** what makes it meta-GGA. Converting
would return an r2SCAN file that is no longer r2SCAN: structurally valid,
silently a different functional. That is the exact failure mode this project
exists to avoid.

For LDA and GGA the conversion is **unnecessary**: AtomPAW writes UPF itself.
Add `PWSCFOUT` to the deck, or simply do not ask for PAW-XML output.

So PAW-XML → UPF is either not needed or not honest, and neither case wants a
converter.

### OpenMX `.vps` → UPF

An ADPACK `.vps` holds **semilocal** potentials — one curve V*l*(r) per
channel, j-dependent, on a logarithmic grid. UPF wants the **separable
Kleinman-Bylander** form: projector functions β*l*(r) and a D*ij* matrix.

Going from one to the other means choosing a local channel and constructing
projectors from the semilocal potentials. That is building a new
pseudopotential, not relabelling a file — and its quality would depend on
choices ADPACK never made.

The `.vps` file does carry a `<project.energies` block, but it holds sign
conventions, not projector functions. `Blochl.projector.num` in the input deck
is a generation setting, not data in the output.

Use ADPACK's output with OpenMX, which is what it is for, or generate with an
engine that writes UPF.

### GTH → UPF

A GTH file is a dozen analytic coefficients, not a radial table. QE's own
`upfconv.x` lists `.gth` as **"DOES NOT WORK"**. Producing a UPF means
sampling the analytic form onto a grid — a construction, not a conversion.

CP2K, CPMD and ABINIT read GTH directly.

## Cross-family conversion is out of scope

NC → US, US → PAW and the reverse are not registered in either direction, and
a test asserts they are not. An ultrasoft pseudopotential is not a
norm-conserving one in a different file layout; it is a different physical
object built from a different calculation. `convert.sh` transforms files. It
does not reinvent pseudopotentials.

## Provenance

Every conversion writes `<output>.provenance` beside the result:

```
source.file, source.format, target.format,
conversion.path, conversion.kind,
converter, converter.version, convert.module, date
```

When the source run recorded an engine, `source.engine.*` is carried forward
so the chain from generator to converted file stays unbroken. Any information
the conversion dropped is recorded as `information.lost` — losses are recorded
as losses, not omitted because the conversion "worked".

## Two traps in `upfconv.x`

Worth knowing if you call it directly.

**It exits 0 whether or not it succeeded.** A file it cannot read gives
`readpp: file X could not be read` / `Cannot read file, stopping` and status
zero. The log is the authority, not `$?`.

**It names its own output and does not say so.** Converting to UPF v2 it
writes `<name>.cpi.UPF2`, not `<name>.UPF`. Globbing for the expected name
reports a successful conversion as a failure.
