# Change the parameters

Every flag here modifies a published recipe. When you use one, the output is
**tagged** so it cannot be mistaken for the library's own file — `-rc1p05`,
`-ch1s`, and so on — and the change is recorded in `PROVENANCE.txt`.

Start by looking at what you are changing:

```bash
pseudoforge recipe Fe -t paw -p psl-high -x pbe
```

## Cutoff radii

The main lever. Larger radii mean a softer, cheaper, less transferable
pseudopotential; smaller means harder and more accurate.

```bash
pseudoforge generate -e Fe -t paw -p psl-high -x pbe --rcut-scale 1.10 -o ./out
```

scales every `rcut` and `rcutus` in the recipe by 1.10, and tags the output
`-rc1p10`.

!!! warning "Radii must not overlap in your structure"
    A cutoff radius larger than half the shortest bond in your material means
    two atoms' pseudised regions overlap, and the result is nonsense that often
    still converges. Check against your actual geometry, not against an
    abstract idea of "soft".

## The local channel

```bash
pseudoforge generate ... --lloc 0       # use l=0 as local
pseudoforge generate ... --lloc -1      # build the local potential from the AE potential
pseudoforge generate ... --rcloc 1.6    # matching radius for the local channel
```

`lloc = -1` generates the local potential from the pseudised all-electron
potential rather than reusing a channel. It is often the cure for a ghost state,
and it is what the auto-fix engine reaches for on a `chi` failure.

## The reference configuration

```bash
pseudoforge generate -e Fe -t paw -p psl-high -x pbe --config '[Ar] 4s1 4p0 3d7' -o ./out
```

Replaces the recipe's reference configuration entirely. This is the most
powerful and most dangerous flag here — it changes which electrons are valence
and what the atom being pseudised actually is.

!!! danger "Count your electrons"
    A noble-gas shorthand includes everything up to that element. `[Xe]` is 54
    electrons and does **not** contain 4f, which first fills at Z=58. Writing
    `[Xe] 4f14` for caesium asks for 68 electrons in an atom with 55, and
    `ld1.x` will compute a negative valence charge, write the file, and exit 0.

    That is not hypothetical — it is a real defect in upstream PSlibrary,
    documented in [Errata](../reference/errata.md).

A **negative occupation** is `ld1.x`'s marker for an unoccupied channel, not an
error: `3d-2` means "include d scattering, with no electrons in it".

## Valence charge

```bash
pseudoforge generate ... --zval 10
```

Rarely needed — the engine computes it from the configuration. Supplying one
that disagrees produces a `valence` failure, which is deliberately **not**
retried, because no radius change can reconcile arithmetic.

The usual mistake is `--zval` together with `--core-hole`. A core hole *raises*
the valence charge by one:

$$ z_{\text{valence}} = Z - n_{\text{core}} $$

Drop `--zval` and let the engine do it.

## Nonlinear core correction

```bash
pseudoforge generate ... --nlcc on --rcore 1.2
pseudoforge generate ... --nlcc off
```

Necessary for spin-polarised calculations and for alkali and transition metals;
cheap; usually already on in a library recipe. `--rcore` sets where the core
charge is pseudised — smaller is more accurate and harder.

`--rho0` passes a value through to `rho0` in the `&inputp` namelist.
PseudoForge does not interpret it; see the `ld1.x` documentation in the Quantum
ESPRESSO distribution for what it means.

## Core holes

```bash
pseudoforge generate -e Cu -t paw -p psl-high -x pbe --core-hole 1s -o ./out
```

For XPS and XAS. The noble-gas shorthand is expanded automatically first — you
cannot punch a hole in a shell hidden inside `[Ar]`. A shell the element does
not have is refused rather than producing a file tagged as having a core hole
it does not have.

Worked through in [Tutorial 4](../tutorials/04-copper.md).

## Extra projectors (ld1.x only)

```bash
pseudoforge generate ... --projector 3D:0.5 --projector 4P:1.0
```

Adds a channel at a fixed reference energy, in Ry. Two projectors in a channel
make it transferable across a range of occupations — which is why PSlibrary's
iron has two `3D` lines, one occupied and one empty at 4.50 Ry.

The flag is `ld1.x only`. It is not implemented for ONCVPSP,
AtomPAW, GTH, USPP, fhi98PP, ADPACK or APE: each of those builds its own
deck layout and would silently ignore the flag while still stamping `-xp` into
the file name. PseudoForge refuses `--projector` on those engines rather
than produce a file whose name promises a change the deck does not
contain. To add a second projector to one of them, edit the deck for
that engine directly (see [write-a-recipe](write-a-recipe.md)).

## Augmentation (US and PAW)

```bash
pseudoforge generate ... --augfun PSQ      # AE | PSQ | BESSEL | GAUSS | BG
pseudoforge generate ... --rmatch 0.9
```

The shape of the augmentation functions, and where they match. The auto-fix
engine changes these on an `augmentation` failure.

## Radial grid and SCF

```bash
pseudoforge generate ... --grid -7.0:0.0125:100.0    # xmin:dx:rmax
pseudoforge generate ... --beta 0.1 --tr2 1.0d-14    # mixing, convergence
```

Reach for these when an element will not converge, or let the auto-fix engine
try them for you — it does exactly this on `scf` and `grid` failures.

## Spin-polarised generation

```bash
pseudoforge generate ... --lsd
```

Generates from a spin-polarised reference atom. **This is not what you need for
a magnetic solid-state calculation** — magnetism happens in `pw.x`, via
`nspin = 2`. Use `--lsd` only when you specifically want an open-shell
reference configuration.

## GIPAW reconstruction

```bash
pseudoforge generate ... --gipaw
```

Adds the reconstruction data `gipaw.x` needs for NMR chemical shifts, EFGs and
`xspectra.x`. Costs nothing at run time and makes the file larger.

## Naming

Any flag on this page tags the generated file automatically — `-rc1p10`,
`-ch1s`, and so on — so a modified recipe cannot produce a file that looks like
the library's own. The tag is derived from the modification and is not
settable by hand.

## Keeping what you worked out

```bash
pseudoforge recipe save fe-soft -e Fe -t paw -p psl-high -x pbe --rcut-scale 1.10
```

See [Save and share a recipe](write-a-recipe.md).
