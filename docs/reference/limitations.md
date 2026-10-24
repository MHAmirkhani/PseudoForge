# Limitations

One page, one purpose: state what PseudoForge cannot do and does not
pretend to do. Each entry names the thing that is missing, the reason it
is missing, and where the measurement lives.

The rule this page exists to keep is the same one that governs the rest
of the tool: **refuse rather than mislabel.** A pseudopotential file
labelled for a calculation it was not made for is worse than a refusal,
because the refusal is visible at the command line and the wrong file is
not.

---

## Formats that cannot be produced here

### UPF v1 (legacy text)

Quantum ESPRESSO 7.x's `ld1.x` no longer recognises the
`upf_v1_format` namelist key that selected the v1 layout, and no other
engine here writes it. `--upf 1` is refused:

```text
ERROR UPF v1 is not supported by the Quantum ESPRESSO in this build.
  QE 7.x's ld1.x no longer recognises the upf_v1_format namelist key, and
  no other engine here writes UPF v1.  Use --upf 2 (the default), or run
  an older QE (<= 6.x) if you need v1 for a legacy reader.
```

Reading v1 files is unaffected: `pseudoforge validate`, `import` and
`convert` all dispatch on the file's own header. Producing a new one
from the engines PseudoForge ships is what is not available. See
[Convert between formats](../how-to/convert-formats.md#upf-v2-only-v1-is-not-produced).

### PSML

ONCVPSP itself rejects `psfile=psml` in its own validator
(`check_data.f90:57`), so the format was never producible by an
engine PseudoForge drives. The registry entry was removed rather than
shipped as a promise the tool could not keep. See
[Formats and conversions](formats.md).

### Meta-GGA UPF

UPF has no field for the kinetic-energy density that makes a meta-GGA
functional meta-GGA. Writing an r2SCAN dataset into a UPF would produce
a file labelled `R2SCAN` whose numbers are PBE. AtomPAW's UPF
writer refuses it cleanly:

```text
XC functional not compatible with atompaw2UPF!
```

A meta-GGA run produces PAW-XML and the ABINIT PAW dataset instead,
read by ABINIT and GPAW. For Quantum ESPRESSO, the [proxy path](../how-to/choose-a-functional.md#path-a-the-proxy-any-engine-any-profile)
generates a GGA pseudopotential under the correct GGA name and records
both names in the provenance.

---

## Conversions that do not exist

Full detail on each is in [Formats and conversions](formats.md); this is
the summary.

| From | To | Kind | Why |
|---|---|---|---|
| `cpi`, `fhi`, `cpmd` | `upf` | refused | QE 7.x's `upfconv.x` lists them in its help but its reader dispatch (`read_ps_new`) has no branch for them, and no `fhi2upf.x` ships |
| `gth` | `upf` | refused | A GTH file is a dozen analytic coefficients, not a radial table. Producing a UPF means sampling onto a grid — a construction, not a conversion |
| `vps` | `upf` | refused | An OpenMX `.vps` holds semilocal V_l(r), one curve per channel; UPF wants a separable Kleinman-Bylander form. Going from one to the other means choosing a local channel and constructing projectors — a new pseudopotential |
| `pawxml` | `upf` | refused | Same as meta-GGA UPF above: UPF has nowhere for the kinetic-energy density |
| `psp8` | `upf` | refused | No tool performs it. ABINIT ships no psp8 converter (checked against 8.10.3, 9.10.3, conda-forge 8.10.2 and 10.0.3), and `upfconv.x` does not list psp8 among the formats it reads |
| `upf` | `psp8` | refused | Same check. psp8 does not need converting to: ONCVPSP writes it natively with `--format psp8` |
| `fhi` | `psp8` | refused | Same check |

A conversion is refused on *physics* when the target needs numbers the
source does not contain; on *no-tool* when the conversion is possible in
principle and nothing performs it. `pseudoforge convert --why <from> <to>`
says which:

```bash
pseudoforge convert --why gth upf
```

---

## Engine restrictions

### OPIUM — d-shell writers crash upstream

Six of OPIUM 4.1.0's ten output writers (`fhi`, `ncpp`, `cpmd`,
`casino`, `champ`, `siesta`) built scratch-file names from
the loop index instead of the real angular momentum, and crashed with
SIGSEGV on any element whose valence l-shells are not contiguous (Fe, Cu,
Zn, Au — every 3d and 5d transition metal).

**Fixed locally.** PseudoForge patches the OPIUM source tree at build
time; the patch lives in `lib/patches/opium/` and is applied between
`build_prepare_src` and `configure`. The upstream tree is
untouched on disk. Reported as
[rappegroup/opium#1](https://github.com/rappegroup/opium/issues/1),
fixed in [rappegroup/opium#2](https://github.com/rappegroup/opium/pull/2).

When upstream merges, the local patch becomes a no-op. See
[the OPIUM page](engines/opium.md#upstream-bug-six-writers-crash-on-d-shell-elements).

### AtomPAW — `diracrelativistic` incomplete

AtomPAW 4.2.0.6's fully-relativistic path is incomplete. Its own source
stops with `setbasis subroutine not ready for diracrelativistic` before
writing any data set. Only `scalarrelativistic` works. The
`atompaw.profile` declares `rel_available=scalar nonrel`, so
`-r full` is refused before anything runs.

The same source also refuses meta-GGA with a relativistic solver: r2SCAN
is `nonrel` only. See
[the AtomPAW page](engines/atompaw.md#constraint-1-non-relativistic-only).

### AtomPAW — `type="LDA"` on meta-GGA output

AtomPAW's PAW-XML writer records the functional as:

```xml
<xc_functional type="LDA" name="MGGA-R2SCAN-001"/>
```

The `type` attribute says LDA on a meta-GGA dataset; only `name` is
correct. Read `name`, not `type`. PseudoForge checks for this
combination on every AtomPAW output and warns, and the warning reaches
the run's `PROVENANCE.txt`. Not yet reported upstream at the time of
writing. See
[the AtomPAW page](engines/atompaw.md#upstream-defect-typelda-on-meta-gga-output).

### APE — no GGA path for open-d transition metals

Ti, Fe, Cu, Zn and Ag fail with `-x pbe`: the occupied d shell is
driven unbound during the SCF. All five generate normally with `-x pz`.
The cause is not established; APE's own shipped chromium test fails the
same way when only the functional is changed. Use `ld1` or `oncvpsp`
for these elements.

APE is also **not in the pre-built store**. See
[the APE page](engines/ape.md).

### ADPACK — 29 elements, full-relativistic only

ADPACK ships a fixed set of 29 input decks. There is no synthesised
fallback for elements outside them: an ADPACK deck fixes the scheme, the
local channel and the per-channel radii that were chosen by hand, and
inventing them would mean issuing a PseudoForge construction under
ADPACK's name. One of the 29, tellurium, is declined by ADPACK's own
Troullier-Martins root-finder on the radii as shipped. See
[the ADPACK page](engines/adpack.md).

---

## Family restrictions

### Meta-GGA

For Quantum ESPRESSO: use the [proxy path](../how-to/choose-a-functional.md#path-a-the-proxy-any-engine-any-profile)
and say so in your methods section. UPF cannot hold the kinetic-energy
density; QE 7.x cannot read a meta-GGA UPF even if one were written.

For ABINIT and GPAW: [AtomPAW generates r2SCAN for real](../how-to/choose-a-functional.md#path-b-atompaw-generates-r2scan-for-real),
as PAW-XML and ABINIT, non-relativistic only. Every element AtomPAW
covers is in the pre-built store under
`~/pf-native/atompaw/paw/r2scan/nonrel/pseudos/`.

### Hybrids (HSE, PBE0, B3LYP) and vdW

No atomic code PseudoForge drives implements them. PseudoForge runs the
semilocal parent and labels the file for it:

| Requested | Generated | Parent |
|---|---|---|
| `pbe0`, `hse`, `scan0`, `gaupbe` | PBE | PBE |
| `b3lyp`, `x3lyp` | BLYP | BLYP |
| `vdw-df`, `optb88-vdw` | revPBE / optB88 | semilocal exchange |
| `vdw-df2`, `vdw-df-cx`, `rvv10` | PBE | PBE |
| `vdw-df2-b86r` | optB86b | optB86b |

The file carries `dft=`<parent>`, the provenance records both names,
and the run's report says so. This is standard practice — the
pseudopotential library the field uses is built on GGA. See
[Choose a functional](../how-to/choose-a-functional.md).

---

## Flags with restricted scope

### `--projector`

**ld1.x only.** Only `recipe_apply` consumes `SPEC[extra_projectors]`,
and only `ld1`'s deck path calls it. Every other engine builds its
own deck layout and would ignore the flag while still stamping `-xp`
into the file name. Refused on ONCVPSP, AtomPAW, GTH, USPP, fhi98PP,
ADPACK and APE:

```text
ERROR --projector is only available with ld1.x in this build.
```

### `--rcut-scale`

**ld1, oncvpsp, opium, ape.** Refused on every other engine before
anything runs. In earlier versions it was accepted by all of them,
applied by one, and still stamped `-rc<f>` into the file name of
the rest.

### `--upf 1`

Refused. See [UPF v1](#upf-v1-legacy-text) above.

---

## The store

### What is not in it

**APE** — not shipped, for the two reasons on
[the APE page](engines/ape.md). Run `pseudoforge engines build ape` and use
it locally if a libxc functional no other engine carries is what you
need.

### What is in it under a condition

Some libraries publish a family their engine cannot generate. GBRV's
PAW sets come from a different code; PseudoDojo's PAW tables likewise.
Those profiles are marked `import only` and the site links to the
authors' own copy rather than rehosting it. See
[Coverage](coverage.md).

---

## Installation limitations

- Quantum ESPRESSO is not bundled. It is downloaded and built on demand (500 MB, ~20 minutes) after a prompt. To install it yourself, see <https://www.quantum-espresso.org/>.
- Engine sources are fetched from `engines-src/` in the repository and verified against `engines-src/MANIFEST.txt`.
- `install.sh --deps` targets Debian, Fedora, Arch, and macOS.

---

## What is not a limitation

Two things read as limitations and are not, and the difference matters
enough to write down.

**Spin-orbit coupling** is fully supported where the engine supports it:
`ld1` with `-r full`, ONCVPSP with `-r full`, OPIUM's
frl writers. The meta-GGA path is the exception because AtomPAW's
relativistic solver is not implemented, not because PseudoForge declines
the request.

**A pseudopotential generated with a proxy functional** is not a
mislabelled file. The name says PBE because the file is PBE; the
provenance says `functional.requested=r2scan` because that is what the
user asked for. Both are true, and the report prints both.

---

## How to report a limitation this page does not name

The reference pages here are generated from the code where they can be,
and checked by `tests/test_docs.sh`. A limitation that is real and
not stated is a bug in the documentation, not only in the code.

Reproduce it, capture the exact command and the exact output, and open
an issue on the [project repository](https://github.com/MHAmirkhani/pseudoforge).
