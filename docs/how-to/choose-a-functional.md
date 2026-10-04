# Choose a functional

One rule dominates everything else on this page:

!!! danger "The pseudopotential must be generated with the functional you will run with"
    A pseudopotential encodes how the core screens the valence electrons, and
    that screening is functional-dependent. Using a PBE pseudopotential in an
    LDA calculation is a real, measurable error — not a formality, and not
    something that cancels.

    `pseudoforge generate -x pbe` then `input_dft = 'LDA'` in `pw.x` is wrong.
    Regenerate.

There is one systematic exception, meta-GGA and hybrids, at the bottom;
meta-GGA in particular now has a *real* generator (AtomPAW) as well as the
proxy path, and both are documented there.

## What is available

```bash
pseudoforge list functionals
```

```text
  LDA
    pz             Perdew-Zunger (LDA)                      dft=LDA
    pw             Perdew-Wang (LDA)                        dft=PW
    vwn            Vosko-Wilk-Nusair (LDA)                  dft=VWN

  GGA
    pbe            Perdew-Burke-Ernzerhof                   dft=PBE
    pbesol         PBEsol (solids)                          dft=PBESOL
    revpbe         revPBE                                   dft=REVPBE
    pw91           Perdew-Wang 91                           dft=PW91
    blyp           Becke-Lee-Yang-Parr                      dft=BLYP
    wc             Wu-Cohen                                 dft=WC
    ...

  metaGGA
    scan           SCAN                                     generated with PBE
    r2scan         r2SCAN                                   generated with PBE
    ...

  hybrid
    pbe0           PBE0                                     generated with PBE
    hse            HSE06                                    generated with PBE
    b3lyp          B3LYP                                    generated with BLYP
```

The right-hand column is the important one. `dft=PBE` means the engine
generates PBE itself. `generated with PBE` means it does not, and PBE is used
as a proxy — see below.

## Which one

**Solids, general purpose**
: `pbe`. The most widely used GGA, and what most of the literature you will
  compare against used.

**Solids, where geometry matters**
: `pbesol`. PBE is fitted to molecular data and overestimates lattice constants
  of solids by around 1%. PBEsol restores the gradient expansion for exchange
  and does markedly better on lattice constants and bulk moduli. Choose it when
  you care about structure; choose `pbe` when you are comparing against PBE
  numbers.

**Reproducing older work**
: `pz` or `pw` for LDA-era papers, `pw91` for the early 1990s. Not because LDA
  is better, but because reproducing a calculation means reproducing its
  functional.

**Molecules, chemistry conventions**
: `blyp`, or `b3lyp` via its BLYP proxy.

**Layered materials, weak interactions**
: The vdW-corrected functionals, with the same proxy caveat.

**Where accuracy matters more than cost**
: `r2scan`. Substantially better than GGA for a wide range of solids. Read the
  next section before using it.

## Meta-GGA and hybrids: the proxy, and one real generator

Meta-GGA functionals use the kinetic-energy density. Hybrids mix in
exact exchange. Almost no atomic code implements either, and the
pseudopotential libraries the field uses are built on GGA datasets.

There are **two paths** in PseudoForge, and they are different enough to
warrant being read separately.

### Path A — the proxy (any engine, any profile)

Ask any GGA-backed profile for a meta-GGA functional and PseudoForge
generates the corresponding GGA pseudopotential, names the file for the
GGA it actually contains, and records both names in the provenance:

```text
 NOTE ON THE FUNCTIONAL
   r2SCAN (metaGGA) -- Quantum ESPRESSO ld1.x cannot generate this family;
   generated with Perdew-Burke-Ernzerhof instead.
   The UPF files carry dft=PBE. Use them with R2SCAN in pw.x; that is
   standard practice, but the pseudopotential was not generated
   self-consistently with R2SCAN.
```

The file carries `dft=PBE`, the provenance records both names, and
the report says so. This is the normal and correct way to run a meta-GGA
calculation in Quantum ESPRESSO today, because QE 7.x cannot read a
meta-GGA UPF in the first place: UPF has no field for the kinetic-energy
density. The GGA dataset is what the run consumes.

```text
functional=PBE
functional.requested=r2scan
```

If you publish, say so in your methods section — *"r2SCAN calculations
used PBE-generated PAW datasets"* — which is what almost every r2SCAN
paper already does.

### Path B — AtomPAW generates r2SCAN for real

AtomPAW carries its own r2SCAN implementation (`src/excor.F90`, `r2scanmod`),
not libxc's. Ask it, and there is no proxy, no note, and no mislabelled
GGA:

```bash
pseudoforge generate -e Si -t paw -x r2scan -r nonrel -p atompaw -o ./out
```

```text
functional=R2SCAN
functional.requested=r2scan
```

The output is a PAW dataset in **PAW-XML and ABINIT**, read by ABINIT and
GPAW. It is **not** UPF, and that is a property of the format: UPF has
nowhere to put the kinetic-energy density, so AtomPAW's UPF writer
refuses it cleanly rather than emit a v2 file under a name that promises
meta-GGA.

Two constraints:

**Non-relativistic only.** AtomPAW's meta-GGA path has no relativistic
solver; asking for `-r scalar` or `-r full` is refused before anything
runs. PseudoForge does not silently drop to `nonrel`, because relativity is
physics and choosing it on your behalf would change the reference atom
without saying so. See [Tutorial 6](../tutorials/06-scan.md).

**The native store already ships them.**

```text
~/pf-native/atompaw/paw/r2scan/nonrel/pseudos/
```

Every element AtomPAW covers is there, as `<El>.r2scan-atompaw.xml`
and `<El>.r2scan-atompaw.abinit`. Download them from the site rather than
regenerate locally if all you need is the dataset.

### Which path to pick

| Goal | Path |
|---|---|
| Run r2SCAN in Quantum ESPRESSO | **A** — QE cannot read a meta-GGA UPF in any case |
| Run r2SCAN in ABINIT or GPAW | **B** — a real r2SCAN dataset, no proxy |
| Reproduce a paper that used PBE pseudos with r2SCAN | **A** — that is what the paper did |
| Publish a meta-GGA study with clean provenance | **B** if the code takes PAW-XML, otherwise **A** and say so |

!!! note "The proxy is engine-aware"
    The note is decided by asking whether the functional the engine will
    actually generate differs from the one you asked for — not by looking
    up "meta-GGA" in a table. So the same `-x r2scan` produces a
    warning from `ld1` and no warning from `atompaw`, which is correct in
    both cases. The refusal is not a gap in PseudoForge; it is a property
    of the format.

## Relativity is a separate choice

`-x` and `-r` are independent. Both must match your production calculation:

```bash
pseudoforge generate -e Au -t nc -p sg15 -x pbe -r full -o ./out
```

gives `Au.rel-pbe-oncv.UPF` — the `rel-` prefix marks a fully relativistic set.
See [Tutorial 5](../tutorials/05-gold.md).

## Checking what you have

The functional is in the file, not only in its name:

```bash
grep -o 'functional="[^"]*"' Si.pbe-n-kjpaw_psl.1.0.0.UPF
```

```text
functional="PBE"
```

and `pseudoforge validate <file>` reports it along with the structural checks.
If you have inherited a directory of pseudopotentials and do not know what they
are:

```bash
pseudoforge import ./inherited-pseudos -o ./audit
```

registers them, reads their headers and tests them, so you find out whether
they are consistent with each other before you mix them in one calculation.
