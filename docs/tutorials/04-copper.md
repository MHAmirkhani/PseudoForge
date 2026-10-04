# 4. Copper with a core hole

The first three tutorials chose between recipes. This one **changes** a recipe:
we take PSlibrary's copper and remove one 1s electron, which is what you need
to model X-ray photoemission (XPS) or X-ray absorption (XAS), where the
measurement itself creates a core hole and the final state is not the ground
state.

It is also the first run where something does not work the first time, and you
get to watch the auto-fix engine deal with it.

## What we are asking for

```bash
pseudoforge generate -e Cu -t paw -p psl-high -x pbe --core-hole 1s -o ./04-copper
```

`--core-hole 1s`
: Remove one electron from the 1s shell of the reference atom. The generated
  pseudopotential then describes a copper atom that has a hole in its deepest
  level — which is the atom that exists for the femtoseconds during a core-level
  spectroscopy experiment.

PAW is not optional here. A core-hole calculation asks about the wavefunction
near the nucleus, and PAW is the formulation that keeps a reconstruction back to
the all-electron wavefunction.

## What happens

```text
== Generating ==
INFO  generating 1 element(s) with 4 parallel job(s)
WARN  Cu: chi -> retry 1/2: widen all cut-off radii by 5%
WARN  Cu: chi -> retry 2/2: widen all cut-off radii by 12% and soften the local channel
OK    Cu  ->  Cu.pbe-spn-kjpaw_psl.1.0.0-ch1s.UPF  (2s)
```

```text
 ELEM PSEUDOPOTENTIAL                    STATUS    PARAMS      TRANSFER   ECUT/RHO     NOTE
 ----------------------------------------------------------------------------------------------------
 Cu   Cu.pbe-spn-kjpaw_psl.1.0.0-ch1s.UPF ok       spn.1.0.0   no-data    -            auto-fixed (widen all cut-off radii by 12% and soften the local channel)
```

Three things to read there.

### The file is tagged

`Cu.pbe-spn-kjpaw_psl.1.0.0-ch1s.UPF` — the `-ch1s` suffix is added
automatically. This file is **not** PSlibrary's copper and must never be
confused with it, so it does not get to wear PSlibrary's exact name. Any
modification to a library recipe gets a tag like this; a widened radius gets
`-rc1p05`, and so on.

### The auto-fix engine fired, and said so

The first attempt failed. `chi` is `ld1.x`'s complaint that it could not
construct the pseudo wavefunctions with the radii it was given — which is
unsurprising, because those radii were chosen for a neutral copper atom and we
have just removed an electron from the middle of its core, contracting
everything.

PseudoForge retried twice, widening the cutoff radii, and succeeded. The
important part is that **the fix is in the report and in the provenance**, not
just in a log:

```text
NOTE  auto-fixed (widen all cut-off radii by 12% and soften the local channel)
```

```bash
grep autofix ./04-copper/PROVENANCE.txt
```

```text
autofix.rc_scale=1.12
```

A run that silently changed your radii and reported success would be worse than
one that failed. See [Troubleshoot a failure](../how-to/troubleshoot.md) for
the full list of what the auto-fix engine tries and in what order, and use
`--no-autofix` to turn it off entirely when you want to see the raw failure.

### Transferability says `no-data`

Not a bad grade — no grade. PSlibrary's copper test deck tests a *neutral*
copper atom in five configurations. Those configurations do not describe the
atom we just built, so running them would produce a number about the wrong
thing. `no-data` is the correct output.

Validating a core-hole pseudopotential is done against the experiment or
against an all-electron core-level calculation, not against a ground-state
transferability test.

## What the core hole did to the recipe

```bash
grep config ./04-copper/inputs/*.in
```

```text
   config='1s1 2s2 2p6 3s2 3p6 4s1 4p0 3d10',
```

Two things changed from the stock recipe.

**The noble-gas shorthand is gone.** PSlibrary writes copper's configuration
with a compressed core. You cannot punch a hole in a shell that is hidden
inside `[Ar]`, so PseudoForge expands the configuration to explicit shells
first. Count them: 1 + 2 + 6 + 2 + 6 + 1 + 0 + 10 = 28, one short of copper's
29. That missing electron is the core hole.

**`z_valence` went up, not down.**

```bash
grep -o 'z_valence="[^"]*"' ./04-copper/pseudos/*.UPF
```

```text
z_valence="20.000000000000000"
```

Ordinary `spn` copper has 19 valence electrons — 3s² 3p⁶ 3d¹⁰ 4s¹. This one has
20, and the arithmetic is worth doing explicitly because the intuition points
the wrong way:

$$ z_{\text{valence}} = Z - n_{\text{core}} $$

We removed an electron from the **core**, so $n_{\text{core}}$ went down by one,
so $z_{\text{valence}}$ went **up** by one. 29 − 9 = 20.

!!! warning "The sign trips people up"
    "I removed an electron, so there should be one fewer" is the natural
    reading and it is wrong. The electron was removed from the part that is
    *not* counted in `z_valence`. If you write your own core-hole input by hand
    and set `zval` down by one, `ld1.x` will produce a file and it will be
    wrong in a way nothing checks. PseudoForge does this arithmetic for you and
    records the result.

## Other shells

```bash
pseudoforge generate -e Cu -t paw -p psl-high -x pbe --core-hole 2p -o ./04-copper-2p
```

1s is the K edge, 2s the L₁, 2p the L₂,₃. The shell you choose is the edge you
are modelling. A shell the element does not have is refused rather than
silently ignored.

## Using it

A core-hole pseudopotential is used for **one atom** in your cell — the
absorbing atom — with ordinary pseudopotentials on every other atom of the same
element. That means two species in `pw.x`:

```text
ATOMIC_SPECIES
  Cu   63.546  Cu.pbe-spn-kjpaw_psl.1.0.0.UPF
  Cu1  63.546  Cu.pbe-spn-kjpaw_psl.1.0.0-ch1s.UPF
```

and `Cu1` placed at the site you are exciting. Use a supercell large enough
that the core holes in periodic images do not see each other, and remember the
cell now carries a net charge unless you compensate it.

For the XAS spectrum itself you will want `xspectra.x` from Quantum ESPRESSO,
which additionally needs GIPAW reconstruction data — see `--gipaw`.

---

Next: [Gold, fully relativistic](05-gold.md) — a different engine, spin-orbit
coupling, and a warning that looks alarming and is not.
