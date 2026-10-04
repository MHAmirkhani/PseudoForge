# Roadmap

The nine layers of pseudopotential construction, what PseudoForge covers, and
what is left. **Coverage is claimed only where it has been run and checked**;
where a layer is genuinely impossible that is stated with the reason rather
than left as an open item.

`tests/test_roadmap.sh` checks the claims on this page against the code, so a
status here cannot quietly stop being true. It exists because this page was, for
a while, wrong in four places at once.

**Version 1.3.0 · GPL-2.0-or-later · Mohammad H. Amirkhani · DOI not yet
minted**

---

## 1. The nine layers

| # | Layer | Decides | Status |
|---|---|---|---|
| 1 | XC functional | the exchange-correlation approximation | **solved** — LDA, GGA; meta-GGA natively in AtomPAW, by documented proxy elsewhere |
| 2 | Relativity | non-relativistic / scalar / full (SOC) | **solved** |
| 3 | Formulation | NC / US / PAW | **solved** |
| 4 | Core–valence partition | which electrons are valence, semicore, core | **solved** — including core holes (`--core-hole`) |
| 5 | Pseudisation scheme | TM, BHS, Kerker, RRKJ, ONCV, Vanderbilt, GTH | **solved** for plane-wave families |
| 6 | Key parameters | `rc`, `lloc`, `config`, pseudisation energies | **solved** for the four engines with `--rcut-scale` — `pseudoforge optimise` sweeps the radii and picks by measured transferability and cutoff. Channels are scaled together. See §4 |
| 7 | NLCC | nonlinear core correction | **solved** |
| 8 | Validation | log derivatives, ghosts, transferability | **solved** — per-engine, `lib/validate.sh` |
| 9 | Format conversion | UPF, psp8, fhi, GTH, OpenMX, … | **solved** — `lib/convert.sh`, 13 declared paths: 4 exact, each proven by bulk-Si energies in `pw.x`; 9 refused, each with a reason taken from upstream source. See §4 |

---

## 2. Current state

**Nine engines**, four interfaces, 922 tests across 32 suites.

| engine | families | notes |
|---|---|---|
| `ld1` | NC US PAW | Quantum ESPRESSO's atomic code; reproduces PSlibrary byte-identically, bar the declared errata |
| `oncvpsp` | NC | linked against libxc; **no meta-GGA code path** |
| `uspp` | US | Vanderbilt's own generator |
| `fhi98pp` | NC | QE 7.x cannot convert its output to UPF — upstream's dispatch, not ours |
| `opium` | NC | many output formats from one generation |
| `gth` | NC | analytic GTH/HGH; 322/322 reproduced byte-identically |
| `atompaw` | PAW | the only real meta-GGA path; non-relativistic only |
| `ape` | NC | libxc-backed; LDA covers all tested elements, **no GGA for open-d metals — §3.1** |
| `adpack` | NC | 29 vendor decks; OpenMX `.vps` |

**Four interfaces**: CLI, wizard, JSON, REST — all on one core through the
[sink contract](../architecture/sink-contract.md).

**Format conversion**: 13 declared paths — 4 `exact`, 9 `refused` with a
reason. Every exact path is proven the only way that settles it: `pw.x` reads
the source format itself, and gives the identical bulk-Si energy from the
source and from the conversion. `psp8` is **generated**, not converted to.
See [Formats and conversions](../reference/formats.md).

---

## 3. What is actually outstanding

### 3.1 APE — no GGA path for open-d transition metals *(cause established, upstream)*

This was carried as "five d-shell elements fail, cause not established". The
cause is now established, and it is not the elements.

Measured 2026-09-27, `--engine ape`, `pseudoforge-auto`, all seven elements:

| functional | result |
|---|---|
| `-x pz` (LDA) | **Ti, Fe, Cu, Zn, Ag, Br, Au — 7 of 7 generate** |
| `-x pbe` (GGA) | Br and Au generate; Ti, Fe, Cu, Zn fail `3d is unbound`, Ag fails `4d is unbound` |

**APE has no working GGA path for an atom with an open d shell**, and that is
upstream's, reproducible from APE's own file. Its shipped chromium deck,
`testsuite/all_electron/02-scalar_rel.01-no_spin.inp`, passes as distributed
with `lda_x_rel + lda_c_vwn` and fails with exactly this message when the one
line naming the functional is changed to `gga_x_pbe + gga_c_pbe`. **APE's test
suite contains no GGA case at all** — every functional in it is an `lda_*` — so
the combination has never been exercised upstream.

Ruled out here before attributing it, one at a time: the order of the orbitals
in the deck, the empty p channel, whether the d shell is pseudised at all (it
fails in the all-electron stage, before pseudisation), libxc's density
threshold from 1e-16 to 1e-6, numerical versus analytical XC derivatives, the
radial mesh extent from 15 to 140 bohr and its point count, the eigensolver
tolerance, and the SCF iteration cap. LDA succeeds in every one of those
configurations; no GGA succeeds in any.

The mechanism, for whoever picks it up: `states_batch.F90` asks
`wavefunctions_n_bound_states` how many bound states the l channel holds, and
that function counts nodes of a trial integration at the top of the well.
Under GGA the l=2 count comes back short, so an occupied d is classified
unbound and the run aborts.

**Not patched.** Changing a solver's bound-state heuristic is a physics change,
and there is no reference here to verify the result against. `pseudoforge` now
says so instead of repeating the engine's four words:

```text
State: 3d is unbound -- APE has no working GGA path for an open-d transition
metal. Its own chromium test fails the same way when only the functional is
changed. Use -x pz with APE, or --engine ld1 or oncvpsp for PBE.
```

The auto-fix fallback that rescued bromine **does not fire** here and should
not: it keys on `multiroot_solve_system`, which is a failure of the
Troullier-Martins construction, while this aborts earlier, in the
all-electron solve. The state file records `attempts: 0`. Widening that
trigger to catch both would change which shell is pseudised for elements that
already work.

Use `-x pz` with APE, or `ld1`/`oncvpsp` for GGA.

!!! warning "\"7 of 7 generate\" meant a file was written, not that it was usable"
    Checking APE's output in `pw.x` — rather than in PseudoForge's own
    validator — found that **every APE file was unusable in Quantum ESPRESSO
    as written**, and fixed three separate causes:

    | fault | measured | fix |
    |---|---|---|
    | APE writes UPF v1 with the functional field **blank** | pw.x: `unrecognized dft` | the functional the deck ran is written in, for LDA and GGA only — for meta-GGA QE's name is ld1's *proxy* parent, which would mislabel the file |
    | QE 7.6 **misreads APE's v1 layout** | the same Si pseudopotential: 645 kbar read as v1, 46 kbar rewritten as v2 (ONCVPSP: 25) | rewritten as v2 through the upfconv wrapper the USPP path already uses; no number changes |
    | APE's own log reports a **ghost state** and nothing read it | bulk Si −59.73 Ry where ONCVPSP gives −15.76 — electrons in the ghost. The pressure, 39 kbar, looked fine | on that line only, each channel is tried as local and the first APE itself calls clean is taken, and recorded. If every channel ghosts, the element fails |

    Ruled out before blaming the v1 reader: V_loc's units (its tail is −2Z/r
    in Rydberg), the D_ij scale, the cut-off radii, the radial grid (PP_RAB
    matches dr/di) and the charge (PP_RHOATOM integrates to 4.0000).

    After the fixes APE's Si PBE gives **−15.761 Ry against ONCVPSP's
    −15.763**; the seven LDA elements are rewritten as v2 and name their
    functional. APE's copper is hard, not broken: −4,781 kbar at 60 Ry,
    +29.6 kbar at 200 Ry. `tests/test_engine_output.sh` holds all of it.

!!! warning "This was previously reported as solved. It was not."
    `tests/test_ape.sh` checks **deck construction**, not generation — it says
    so in its own header, and it runs without APE installed. Its 31 passing
    checks say the deck is built correctly; they never said APE accepts it, and
    the difference was not noticed.

    `tests/test_ape_live.sh` now runs the engine, so the claim and the
    measurement are the same thing.

Use `ld1` or `oncvpsp` for these elements.

### 3.2 Layer 6 — the `rc` optimiser *(built; limits stated)*

`pseudoforge optimise` sweeps `--rcut-scale`, runs `generate` per rung, and
picks by a stated rule from what the pipeline already measures: generated,
transferability at least `--min-grade`, then the lowest converged cutoff — or,
without a cutoff scan, the largest passing scale. `no-data` is never eligible.
[How-to](../how-to/optimise-radii.md).

On Si PBE with ONCVPSP it chose scale 1.1: 15 Ry and max |Δε| 0.00119 Ry,
against the default radii's 18 Ry and 0.00173 — softer *and* more transferable.

Building it found that `--rcut-scale`, which it rests on, was applied by ld1
alone: six engines ignored it, and four of them still named their output
`-rc1p2`. It now works on ld1, oncvpsp, opium and ape, and is refused with a
reason elsewhere.

**What is still open**, as limits rather than bugs: all radii are scaled
together, so channels are not optimised independently; a lattice constant is
not fitted; and uspp, atompaw and fhi98pp have no `--rcut-scale`, because
scaling their coupled radii has not been verified.

### 3.3 Engine citations *(resolved — no unverified engine citations)*

ADPACK, AtomPAW and OPIUM were carried as unverified. All three are now
resolved, and resolved as something different from the others: **none of the
three authors asks for a citation anywhere** — distribution, manual or
website, each read, not skimmed — so they are recorded as `no-request` and
print the reference the authors' *own* documentation gives for the method,
labelled as exactly that.

| engine | checked | reference |
|---|---|---|
| ADPACK | the 2.2 user's manual in full, incl. §14 and the bibliography | its ref. [15], for ADPACK's own contribution (PAOs under confinement): Ozaki, PRB **67**, 155108 (2003); Ozaki & Kino, PRB **69**, 195113 (2004) |
| AtomPAW | distribution, Holzwarth's page, ABINIT's AtomPAW page | the code's own paper, ABINIT's ref. [1]: Tackett, Holzwarth & Matthews, CPC **135**, 329 (2001) |
| OPIUM | distribution, opium.sourceforge.net, its scientific-references page | ref. [2], for the `opt` scheme our decks select: Rappe *et al.*, PRB **41**, 1227 (1990) |

Every DOI was resolved to the title recorded beside it. ADPACK's recorded URL
had gone dead (404) and now points at the manual. See
[the citation rule](adding-an-engine.md#9-cite-it) and
[Data provenance](../reference/data-provenance.md#citations-and-licences-libmetadatash).

---

## 4. Solved, with the measurement

Kept because a roadmap that lists only what is left gives no way to check what
was claimed.

**Layer 9 — format conversion.** `lib/convert.sh`: 13 paths, 4 exact and 9
refused. This was carried as "four paths registered and not demonstrated", and
running them properly overturned more than it confirmed:

| path | was | measured | now |
|---|---|---|---|
| `van → upf`, `vdb → upf` | exact, "passes validation" | **pw.x could not open the result** — a 2,496-character `PP_QFCOEF` row past QE's 1024-character reader limit. The fix existed but only on the `generate` path | exact: `.van` native and converted give −15.90704670 Ry |
| `rrkj3 → upf` | exact, never run | failed: QE matches only uppercase `.RRKJ3` | exact: −22.99954954 Ry both ways |
| `upf → xml` | exact, "passes validation" | — | exact: −15.76231144 Ry both ways |
| `cpi`, `fhi`, `cpmd → upf` | exact / "yes *" | QE 7.x `upfconv.x` has **no reader** for them — `read_ps_new` dispatches `.psml`, `.van`, `.RRKJ3`, `.gth` and nothing else; no `fhi2upf.x` ships | refused, `no-tool` |
| `psp8 ↔ upf`, `fhi → psp8` | exact, via `pspconvert` | `pspconvert` does not exist | refused, `no-tool` |

Energies are bulk Si, 30/240 Ry, 4×4×4, `conv_thr` 1e-10; the slow suite
re-runs all three. The lesson is in the first row: **validation checks form,
not physics**. The validator now also enforces QE's 1024-character line limit,
taken from `upflib/xmltools.f90`.

One caution belongs to the RRKJ3 *format*, not the conversion: ld1.x's RRKJ3
of a PSlibrary deck is already 2.2 eV per Si cell away from the UPF ld1.x
writes from that same deck, because the old layout has no l-resolved
augmentation. The conversion reproduces the RRKJ3 exactly; it cannot restore
what the RRKJ3 never held. Convert RRKJ3 files you have; do not make new ones
to convert.

The refusals are of two kinds and the difference is reported, because it is
the part a reader can act on: `physics` (the target needs numbers the source
does not contain) and `no-tool` (possible in principle; nothing performs it).
Every conversion writes a `.provenance` sidecar recording source, tool, tool
version and kind.

**psp8, natively.** `--engine oncvpsp --format psp8` writes the file ABINIT
reads, with no intermediate step. `psp8_validate` reads the header — `pspcod`,
`zatom` against the element, `zion`, `lmax`, the projector count, the grid
length — rather than only checking the byte count.

**Layer 4 — core holes.** `--core-hole 1s` expands the noble-gas shorthand,
removes the electron, and lets the engine recompute `z_valence` — which goes
*up* by one, not down. A shell the element does not have is refused rather than
producing a file tagged as having a hole it does not have.
[Tutorial 4](../tutorials/04-copper.md).

**Layer 8 — validation.** Each engine's own analysis, with the method recorded
beside every verdict, because six engines do not measure the same thing.

**ADPACK, ninth engine.** Stack-overflow fix verified: 29 of 29 decks complete,
frame 9,048,480 bytes → under 100 KB, no physics changed (a test asserts no
decimal appears in the patch). Tellurium is handled by an auto-fix retry
(rc × 1.1, then × 1.2), recorded in the provenance.

**Caesium.** Upstream PSlibrary's low-cutoff recipe asked for 68 electrons in
an atom with 55. Corrected through a declared erratum; `z_valence` 9.00,
transferability excellent. [Errata](../reference/errata.md).

**The website.** Four interfaces on one core; a REST API whose routes, shapes
and refusals live in `lib/http.sh`; a static frontend; the documentation served
from the same domain. [Architecture](../architecture/http.md).

---

## 5. Beyond the software

Zenodo DOIs for PseudoForge and for the ADPACK fork, and a JOSS or CPC paper.
Tracked outside this file.

---

## 6. Constraints that do not move

1. **The core is Bash.** External tools are called through `PATH`, never bundled.
2. **No physics changes in a build fix.** Any patch touching a routine,
   tolerance or default is documented as a physics change.
3. **No invented citations.** `Unverified — check the source`, with a named
   TODO, when unknown.
4. **No invented parameters.** A library's name is never stamped on a result
   that did not come from that library's own inputs.
5. **Provenance is recorded for every output.**
6. **The mirror never invents URLs.**
7. **No silent downgrades.** A refusal carries its reason; a lossy conversion
   names what it dropped.
8. **A status is a measurement.** Anything this page calls solved has been run
   and checked, and `tests/test_roadmap.sh` keeps it that way.
