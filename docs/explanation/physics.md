# Choosing the settings

A practical guide to what PseudoForge's options mean physically, and how to pick
them. Every option here maps onto a real `ld1.x` variable; the mapping is given
so you can check the generated deck against the `ld1.x` documentation.

---

## 1. Pseudopotential type

| | `ld1.x` | cost | when |
|---|---|---|---|
| **PAW** | `lpaw=.true.`, `pseudotype=3` | ~45–60 Ry wfc | the default choice; all-electron accuracy for energies, magnetism, EFGs, NMR |
| **US** | `lpaw=.false.`, `pseudotype=3` | ~30–45 Ry wfc | large cells, molecular dynamics, anything where cost dominates |
| **NC** | `pseudotype=2` | ~60–100 Ry wfc | required by many post-SCF codes: TDDFPT, some GW/BSE workflows, EPW, hybrid functionals in practice |

Ultrasoft and PAW both need a charge-density cutoff well above the wavefunction
cutoff — `ecutrho ≈ 8 × ecutwfc` is the usual starting point, against
`ecutrho = 4 × ecutwfc` for norm-conserving. PseudoForge uses those ratios by default
(`DUAL_NC`, `DUAL_US`, `DUAL_PAW` in `~/.pseudoforgerc`).

If a code refuses your pseudopotential, it almost always wants norm-conserving.

### Separable or semilocal?

Norm-conserving pseudopotentials come in two forms, and `--nc-form` picks
between them:

| | `ld1.x` | |
|---|---|---|
| `separable` (default) | `pseudotype=2` | Kleinman–Bylander form: compact and fast, what essentially everyone uses |
| `semilocal` | `pseudotype=1` | one potential per angular momentum; larger files and slower in `pw.x`, but ghost-free by construction |

Reach for `semilocal` when a separable pseudopotential shows ghost states you
cannot remove by changing `lloc`, or when a downstream code demands it.
Semilocal files are tagged `-sl` so the two cannot be confused.

---

## 2. Functional

Use the same functional you will run with, when you can. `ld1.x` can generate
LDA and GGA directly:

```
LDA   PZ (= LDA)  PW  VWN  VWN-RPA
GGA   PBE  PBEsol  revPBE  PW91  BP  BLYP  WC  optB86b  optB88  SOGGA  Q2D
```

PBE is the default and by far the best tested. PBEsol is the usual choice for
solid-state lattice constants and phonons.

For meta-GGA, hybrid and van der Waals functionals `ld1.x` has no atomic solver,
so pseudoforge generates with the accepted semilocal parent and says so — see
[PROVENANCE.md](../reference/data-provenance.md) for the full mapping. This is not a workaround
peculiar to pseudoforge: it is what every public library does, and what people
actually do when they run SCAN or HSE.

**Except with AtomPAW.** AtomPAW generates r2SCAN natively, so `--xc r2scan
--engine atompaw` is a real meta-GGA PAW data set rather than a PBE one under
a meta-GGA name. It writes PAW-XML and ABINIT, not UPF — see
[the AtomPAW page](../reference/engines/atompaw.md). Hybrids remain out of reach everywhere.

### The XC registry is engine-aware

This is a design decision worth stating plainly, because the alternative is a
quiet wrong answer.

Each engine declares which functionals it can generate natively. When a
request names a functional an engine cannot generate, that engine's proxy is
substituted, and the substitution is stamped into the log, the report and the
manifest.

**The proxy is per engine, not global.** The same request resolves differently
depending on what will run:

```
--xc r2scan --engine atompaw    ->  r2scan   (native)
--xc r2scan --engine oncvpsp    ->  pbe      (proxied, and said so)
--xc r2scan --engine ld1        ->  pbe      (proxied, and said so)
```

A single global proxy would have been simpler and wrong: it would hand an
AtomPAW user a PBE data set while their input said r2SCAN, with nothing in the
output to show it. Conversely, marking r2SCAN "native" globally would promise
ONCVPSP users something ONCVPSP stops on — its `functionals.F90` reaches
`XC_FAMILY_MGGA` and halts with *"meta GGA not coded yet"*, whatever libxc it
is linked against.

The authority for "can this engine do it natively" is the engine's own
functional mapper, not a second table, so the two cannot drift apart.

**Do not mix.** A PBE pseudopotential used in an LDA calculation (or the
reverse) is a real error, not a small one. PseudoForge names files after the
functional they were generated with so the mismatch is visible.

---

## 3. Relativity

| | `ld1.x` | when |
|---|---|---|
| non-relativistic | `rel=0` | almost never; light-element test cases |
| scalar-relativistic | `rel=1` | the default up to about Z = 36 |
| full-relativistic | `rel=2` | Z ≳ 37, and mandatory for 5d elements, actinides, and any spin-orbit property |

Full-relativistic pseudopotentials carry the *j*-resolved projectors that
`pw.x` needs for `lspinorb=.true.`. They can also be used in a scalar
calculation, so when in doubt for a heavy element, generate `full`.

Note the file-name convention PseudoForge inherits from PSlibrary: full-relativistic
sets get a `rel-` prefix on the functional tag (`Pt.rel-pbe-spfn-kjpaw_psl…`).

---

## 4. Profile and the semicore question

The profile decides which shells are treated as valence. That single choice
dominates both accuracy and cost.

The variant tag in a PSlibrary file name tells you what is in the valence:

| tag | meaning |
|---|---|
| `s`, `p`, `d`, `f` | that semicore shell is in the valence |
| `spn` | semicore s and p, plus nonlinear core correction |
| `n` | nonlinear core correction, no extra semicore |
| `l`, `ll` | a softer, lower-cutoff variant of the same valence |

`pseudoforge list recipes Fe` shows every variant PseudoForge holds for an element, and
`--variant spn` picks one explicitly.

**When you need semicore states in the valence:**

* alkali and alkaline-earth metals — nearly always (Na, K, Rb, Cs, Ca, Sr, Ba)
* early transition metals — the (n−1)s and (n−1)p shells overlap the valence
* anything under pressure, where core–valence overlap grows
* magnetic systems, where the core polarises
* NMR, EFG, hyperfine and core-level spectroscopy

**When you can skip it:** ordinary main-group chemistry at ambient pressure,
late transition metals in simple environments, and any run where cost is the
binding constraint. That is what `psl-low` is for.

---

## 5. Nonlinear core correction

`nlcc=.true.`, `new_core_ps=.true.`, `rcore=<radius>`

NLCC keeps the core charge in the exchange-correlation functional instead of
pretending the valence density is the whole story. It matters whenever core and
valence densities overlap:

* **essential** for spin-polarised calculations of 3d metals — without it,
  magnetic moments are simply wrong
* **important** for alkali and alkaline-earth metals, lanthanides, actinides
* **harmless but pointless** for closed-shell main-group atoms

`rcore` is where the true core charge is replaced by a smooth model, typically
0.7–1.5 bohr. Too small and the pseudopotential gets hard; too large and the
correction stops describing the real overlap. The library recipes already carry
sensible values — override only with a reason.

---

## 6. Cut-off radii

The card block at the end of a deck carries, per state:

```
3D   3  2   6.00   0.00   1.00   1.40   0.0
^    ^  ^   ^      ^      ^      ^      ^
nl   n  l   occ    ener   rcut   rcutus jj
```

`rcut` is the norm-conserving matching radius, `rcutus` the ultrasoft one
(`rcutus ≥ rcut`). Smaller radii mean a harder, more transferable
pseudopotential and a higher cutoff; larger radii mean the opposite. As a rule
of thumb, `rcut` should sit near the outermost node of the all-electron
wavefunction and comfortably inside half the shortest bond length in the systems
you care about.

`--rcut-scale` multiplies every radius at once — the quickest way to trade
transferability against cost, and the first thing the auto-fix engine reaches
for when the pseudo-wavefunction construction fails.

---

## 7. Projectors and the local channel

More projectors per angular-momentum channel means better transferability and a
lower risk of ghost states, at the price of cost. Add one with

```
--projector 3D:0.5
```

which repeats the `3D` card at a reference energy of 0.5 Ry — exactly how
`ld1.x` is asked for a second projector in that channel. The card is
inserted immediately after the base card and carries the negative of the
base occupation, matching the multi-projector layout PSlibrary itself uses;
a card appended to the end of the block, or one with a positive occupation,
upsets ld1_setup ("mismatch between lloc and l"). `--projector` is
refused on every engine other than `ld1`, because the other engines
build their own deck format and would ignore the flag while still
stamping `-xp` into the file name.

The **local channel** (`lloc`) is the angular momentum treated as purely local:

| `lloc` | meaning |
|---|---|
| `-1` | build the local potential from the all-electron potential, using `rcloc` — PSlibrary's usual choice |
| `0`, `1`, `2`, `3` | use s, p, d or f as the local channel |

Ghost states — spurious bound states below the true valence — usually come from
a bad local-channel choice. If `pw.x` gives nonsense band structures with an
otherwise clean pseudopotential, change `lloc` first.

---

## 8. Augmentation functions (US and PAW only)

`which_augfun`:

| | |
|---|---|
| `PSQ` | pseudised Q, PSlibrary's default; a good balance |
| `AE` | all-electron Q — most accurate, hardest |
| `BESSEL` | spherical Bessel expansion; often rescues a failing augmentation |
| `GAUSS`, `BG` | Gaussian and Blöchl–Gaussian expansions |

`rmatch_augfun` is where the augmentation charge is matched, and must sit inside
the smallest `rcut` in the deck. Errors from `find_qi` almost always mean this
radius is wrong; PseudoForge's auto-fix tries `BESSEL` first and then a tighter
`rmatch_augfun`.

---

## 9. Core-hole pseudopotentials (XPS, XAS, XSpectra)

```
pseudoforge generate -e Cu --core-hole 1s --zval 12
```

PseudoForge expands the noble-gas shorthand in the configuration so the named shell
is explicit, removes one electron from it, and tags the output file (`…-ch1s`)
so it can never be confused with the ordinary pseudopotential.

**Set `zval` yourself.** The core hole changes the valence charge bookkeeping and
`ld1.x` will not guess what you meant; PseudoForge warns if you leave it out. Use the
core-hole pseudopotential on the excited atom only, and the ordinary one
everywhere else in the cell.

---

## 10. Fractional nuclear charge (virtual crystal)

```
pseudoforge generate -e Si --zed 14.5
```

A non-integer `zed` builds a virtual-crystal pseudopotential: an averaged atom
for a disordered alloy site. Output is tagged (`…-z14p5`).

The virtual-crystal approximation smears out exactly the local chemistry that
often drives alloy behaviour. It is cheap and sometimes adequate; check it
against a supercell before trusting it.

---

## 11. GIPAW reconstruction

```
pseudoforge generate -e C,H,N,O --gipaw
```

Adds the all-electron reconstruction data the GIPAW module needs for NMR
chemical shifts and EPR g-tensors (`lgipaw_reconstruction=.true.`, plus
`use_paw_as_gipaw=.true.` for PAW). The files get larger; nothing else changes.

GIPAW is a *method*, not a library — you generate ordinary pseudopotentials with
this extra data block, which is why PseudoForge exposes it as a setting rather than
as a profile.

---

## 12. Grid and SCF controls

`xmin`, `dx`, `rmax` define the logarithmic radial grid,
r(i) = exp(xmin + (i−1)·dx)/Z, out to `rmax` bohr. Defaults are around
`-7.0 : 0.0125 : 100.0`.

* extend `rmax` when the atomic solver cannot bind a diffuse state
* refine `dx` when heavy elements will not converge
* lower `beta` (SCF mixing) to about 0.1 for a stubborn open-shell atom

These are exactly what the auto-fix engine adjusts on an `ascheq` or `do_mesh`
failure.

---

## 13. After generation

1. **Read the transferability verdict.** "marginal" or "poor" means the
   pseudopotential reproduces the all-electron atom badly in configurations it
   was not fitted to. Fix it before using it.
2. **Run a cutoff scan** (`--cutoff-scan`) and use a cutoff at or above the
   recommendation. PseudoForge scans a generic fcc cell; your own system may need
   more.
3. **Check against a known result.** The lattice constant and bulk modulus of
   the elemental solid, against experiment or an all-electron reference, is the
   standard sanity check and takes minutes.
4. **Look for ghost states** in a band structure before trusting a new
   norm-conserving pseudopotential.

A pseudopotential that passes the atom tests can still be wrong for your system.
The tests narrow the risk; they do not remove it.

## Choosing a generator engine

PseudoForge drives nine atomic codes, and which one you want follows from what
you are making. [the engines page](../reference/engines.md) covers building and provenance; this is the
physics of the choice.

| you need | engine | why |
|---|---|---|
| PAW | `ld1` | the only one of the four that makes PAW data sets |
| ultrasoft, lowest cutoff | `uspp` or `ld1 -t us` | Vanderbilt's own code, or PSlibrary's RRKJ construction |
| norm-conserving for QE | `oncvpsp` | multi-projector, accurate, and writes UPF directly |
| norm-conserving, classic schemes | `fhi98pp` | Hamann and Troullier-Martins; `.cpi` only on QE 7.x |

### Norm-conserving: ONCVPSP versus ld1

Both make NC pseudopotentials, and they are not interchangeable.

`ld1.x` builds Troullier-Martins or RRKJ norm-conserving potentials, typically
with one projector per channel. Simple, well understood, and usually hard —
often 80 Ry or more for a first-row element.

ONCVPSP optimises the pseudo-wavefunction directly against a plane-wave cutoff,
with two projectors per channel by default. The result is markedly softer at
the same accuracy, and the extra projector is what keeps ghost states away. If
you are generating NC for a plane-wave code, this is normally the better engine.

### Ultrasoft: USPP versus ld1

`ld1.x`'s RRKJ ultrasoft construction is what PSlibrary uses, and the `psl-*`
profiles reproduce it exactly. Vanderbilt's `uspp` is the original code and the
one GBRV was built with; PseudoForge uses its shipped `Work/` decks.

Prefer `ld1 -t us -p psl-high` unless you specifically want Vanderbilt's
construction: PSlibrary covers far more of the periodic table, and its decks are
reproduced byte for byte.

### A caution about the pseudoforge-constructed decks

When PseudoForge has no library table and no vendor deck for an element, it builds
an ONCVPSP input from the ground-state configuration and a covalent-radius
heuristic. Two things go wrong often enough to expect them:

**Ghost states.** A cut-off radius that is too large, or too few projectors,
puts a spurious bound state in the separable form. ONCVPSP tests for this and
PseudoForge promotes the finding to the status column — a run marked `ok-warn` with
a ghost is not usable, whatever else the report says.

**Unbound channels.** A channel with no occupied state has no eigenvalue to
converge on, so it needs a positive reference energy rather than `ep = 0`.
PseudoForge sets that automatically, but the value it picks (0.1 Ha) is a guess.

Both are why validation is not optional for a `pseudoforge`-provenance file.
Transition metals in particular usually need a real curated deck: an unassisted
construction failed for iron in testing and produced ghosts for oxygen, while
the vendor decks for both worked first time.

## fhi98PP output and Quantum ESPRESSO 7.x

fhi98PP writes `.cpi`/`.fhi`. Quantum ESPRESSO 7.x cannot read either.

QE's `upflib/read_ps.f90` dispatches on file extension, with branches for
`.psml`, `.vdb`/`.van`, `.RRKJ3` and `.gth`; everything else falls through to
`read_ncpp`, which does not understand the FHI layout. `read_fhi` is still
compiled into `upfconv.x` and still advertised by its `-h` text, but nothing
calls it. The known-good sample shipped as `fhi98PP/sample/al:h.cpi` fails the
same way, so this is not a problem with any particular generated file and
renaming extensions does not help.

PseudoForge keeps the `.cpi` under `pseudos/native/` and records why there is no
UPF. The file remains usable: ABINIT reads `.cpi` directly, and fhi98PP's own
`pslp.x` performs genuine ghost-state and transferability analysis on it.

For norm-conserving pseudopotentials destined for Quantum ESPRESSO, use
ONCVPSP (`--engine oncvpsp`) or PSlibrary's NC set (`--engine ld1 -t nc`).

---

## Core-hole pseudopotentials, and the valence charge

`--core-hole 1s` removes one electron from the named shell, for XPS, XAS and
XSpectra work.

```sh
pseudoforge generate -e Cu --core-hole 1s -o ~/pp/cu-corehole
```

**Do not supply `--zval`.** This is the one thing that reliably goes wrong, and
the arithmetic is worth stating plainly.

A core hole leaves one fewer electron in the core. `ld1.x` computes the valence
charge as *Z* minus the core electrons that remain, so a core-hole
pseudopotential carries **one more** valence charge than the neutral one:

| | `z_valence` |
|---|---|
| Cu, PSlibrary `spn`, no hole | 19 |
| Cu, PSlibrary `spn`, 1s hole | **20** |

Both measured. The extra unit is the removed electron, which is no longer
screening the nucleus and therefore belongs to the valence as far as the
pseudopotential is concerned.

`ld1.x` gets this right unaided. Supplying `zval` by hand is what breaks it:

```
ld1_readin: supplied ( 12.00) and calculated ( 20.00) valence
```

That is not a convergence problem and no retry can fix it, so PseudoForge
diagnoses it as `valence`, declines to spend auto-fix attempts on it, and warns
before the run if `--zval` is combined with `--core-hole`.

The output file is named with a `-ch1s` tag. A core-hole pseudopotential is a
different physical object from the neutral one and must never share its name.

## Meta-GGA: PAW-XML and ABINIT only

r2SCAN is generated natively by AtomPAW (`--xc r2scan --engine atompaw`), and
the result is a **PAW-XML or ABINIT dataset, never a UPF**.

This is not a gap in PseudoForge. **UPF has no tag for the kinetic-energy
density.** A PAW UPF carries `PP_AEWFC`, `PP_AE_VLOC`, `PP_AUGMENTATION`,
`PP_BETA`, `PP_DIJ`, `PP_FULL_WFC`, `PP_MULTIPOLES`, `PP_PAW`, `PP_QIJL` and
the rest — and nothing that can hold τ. For a meta-GGA functional that term is
what makes it meta-GGA, so a UPF written from an r2SCAN dataset would no longer
be r2SCAN: structurally valid, silently a different functional.

So `PAW-XML → UPF` is refused rather than performed. See
[CONVERSION.md](conversion.md).

If you need meta-GGA in Quantum ESPRESSO, do what the field does: run the
meta-GGA calculation with a PBE-generated pseudopotential. `--xc r2scan` with
any engine other than AtomPAW does exactly that, says so in the log and the
report, and names the file after PBE rather than after r2SCAN.

The same applies to hybrids (HSE06, PBE0, B3LYP): no public generator produces
them, and the community uses PBE pseudopotentials.
