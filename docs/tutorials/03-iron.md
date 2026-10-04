# 3. Iron, semicore and PAW

Iron is where the fourth layer — the core–valence partition — stops being an
abstraction. Silicon has one sensible answer about which electrons are valence.
Iron has at least two, they cost differently, and the wrong one is wrong in
ways that only show up under pressure or in an unusual oxidation state.

## What we are asking for

```bash
pseudoforge generate -e Fe -t paw -p psl-high -x pbe -o ./03-iron
```

`-t paw`
: **Projector-augmented wave.** PAW keeps a formal reconstruction back to the
  all-electron wavefunction, so all-electron quantities can be recovered from a
  pseudised calculation. That matters for iron specifically: hyperfine
  parameters, electric field gradients, core-level spectroscopy and anything
  else that depends on the wavefunction near the nucleus. It is also as soft as
  ultrasoft, so you are not paying for the privilege.

`-x pbe`
: PBE rather than PBEsol here, because magnetic 3d metals are the case where
  PBE's known behaviour is the one most of the literature is built on. For
  lattice constants alone PBEsol would do better.

## What happens

```text
 project      : ./03-iron
 family       : PAW
 functional   : Perdew-Burke-Ernzerhof (GGA) -- generated natively by Quantum ESPRESSO ld1.x as dft=PBE
 relativity   : Scalar-relativistic (no spin-orbit)
 engine       : Quantum ESPRESSO ld1.x v.7.6 [build 7de3694ef3fd] /opt/espresso/7.6/ld1.x

 ELEM PSEUDOPOTENTIAL                    STATUS    PARAMS      TRANSFER   ECUT/RHO     NOTE
 ----------------------------------------------------------------------------------------------------
 Fe   Fe.pbe-spn-kjpaw_psl.1.0.0.UPF     ok        spn.1.0.0   excellent  -

 1 succeeded, 0 succeeded with warnings, 0 failed, 0 skipped (1 total)
```

```text
Fe	Fe.pbe-spn-kjpaw_psl.1.0.0.UPF	0.000740	0.000500	excellent	ld1 iswitch=2	re-solved in unfitted configurations
```

## Reading the file name

`Fe.pbe-spn-kjpaw_psl.1.0.0.UPF` is not arbitrary. PSlibrary's convention packs
the important choices into the name, and PseudoForge reproduces it exactly:

| Fragment | Meaning |
|---|---|
| `Fe` | element |
| `pbe` | functional. A fully relativistic set would read `rel-pbe` |
| `spn` | **the valence partition** — see below |
| `kjpaw` | Kresse–Joubert PAW. Ultrasoft reads `rrkjus`, norm-conserving `nc` |
| `psl.1.0.0` | PSlibrary version |

The `spn` fragment is the one worth learning:

- `s` — the semicore **s** shell is in the valence
- `p` — the semicore **p** shell is in the valence
- `n` — **n**onlinear core correction is on

So `spn` means the 3s and 3p electrons are treated as valence, not frozen into
the core. That is what `PARAMS spn.1.0.0` in the table is telling you.

## Why the semicore is in the valence

Look at the deck:

```bash
pseudoforge recipe Fe -t paw -p psl-high -x pbe
```

```text
   config='[Ar] 4s2 4p0 3d6',
...
6
3S  1  0  2.00  0.00  0.70  1.20  0.0
4S  2  0  2.00  0.00  0.70  1.20  0.0
3P  2  1  6.00  0.00  1.00  1.30  0.0
4P  3  1  0.00  6.00  1.00  1.30  0.0
3D  3  2  6.00  0.00  1.00  1.40  0.0
3D  3  2  0.00  4.50  1.00  1.40  0.0
```

Six channels are being pseudised, and two of them — `3S` and `3P` — are shells
that a naive treatment would freeze into the core. The frozen core is only
`[Ar]` minus those, i.e. neon plus nothing: 3s² 3p⁶ 3d⁶ 4s² are all valence,
16 electrons.

The reason is overlap. In iron the 3s and 3p orbitals are not much smaller than
the 3d, and in a solid they are not negligible where the neighbouring atom's
charge starts. Freezing them assumes they do not respond to the environment,
which fails under compression, in high oxidation states, and for magnetic
properties that depend on the core polarisation.

The cost is real: 16 valence electrons instead of 8, and cutoff radii down to
0.70 bohr, which means a high `ecutrho`. That is the trade the library made,
and `psl-high` makes it deliberately.

### Seeing the alternative

Some elements ship more than one variant. To see what a profile has for iron:

```bash
pseudoforge list recipes Fe
```

and to generate a specific one rather than the default:

```bash
pseudoforge generate -e Fe -t paw -p psl-high -x pbe --variant spn.1.0.0 -o ./03-iron-spn
```

`psl-alt` is the PSlibrary set that exists precisely to offer different valence
partitions, and comparing against it is the cleanest way to see what the choice
costs:

```bash
pseudoforge generate -e Fe -t paw -p psl-alt -x pbe -o ./03-iron-alt
```

## The two 3D lines

```text
3D  3  2  6.00  0.00  1.00  1.40  0.0
3D  3  2  0.00  4.50  1.00  1.40  0.0
```

The same shell appears twice: once at its bound-state occupation (6 electrons,
energy solved for) and once empty at a fixed reference energy of 4.50 Ry. That
is **two projectors in the d channel**, and it is what makes the
pseudopotential transferable across the range of d occupations iron actually
visits in different compounds. A single-projector d channel would be accurate
at the configuration it was fitted to and drift away from it.

The same pattern appears in the `4P` line: unoccupied, at a reference energy of
6.00 Ry, describing p scattering that iron's ground state does not populate but
its bonding does.

## Spin

Nothing above is spin-polarised, and that is correct: **the pseudopotential is
generated for a spherical, non-spin-polarised atom, and the magnetism happens
in your solid-state calculation.** You do not need a magnetic pseudopotential
to do a magnetic calculation. `nspin = 2` and a starting magnetisation in
`pw.x` is where iron becomes magnetic.

PseudoForge does expose `--lsd` for a spin-polarised *generation* run, which is
occasionally wanted for open-shell reference configurations, but it is not what
you need for ordinary magnetic solid-state work.

What does matter for magnetism is the **nonlinear core correction**, the `n` in
`spn`. Without it the exchange-correlation energy is evaluated on the valence
density alone, which for a 3d metal gets the spin splitting wrong. It is on
here, and it should be.

## Using it

```text
ATOMIC_SPECIES
  Fe  55.845  Fe.pbe-spn-kjpaw_psl.1.0.0.UPF
```

PAW, like ultrasoft, wants `ecutrho` around 8× `ecutwfc`. Iron with semicore is
a hard pseudopotential — do not be surprised by `ecutwfc` of 60–90 Ry. Measure
it:

```bash
pseudoforge generate -e Fe -t paw -p psl-high -x pbe --cutoff-scan -o ./03-iron
```

and for a magnetic calculation remember `nspin = 2`,
`starting_magnetization(1) = 0.4` or similar, and smearing.

---

Next: [Copper with a core hole](04-copper.md) — changing the recipe rather than
choosing between recipes, and watching the auto-fix engine handle the
consequences.
