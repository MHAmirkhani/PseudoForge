# 2. Silicon and transferability

Carbon showed the shape of a run. Silicon shows the part that matters: **how
you know the file is any good.**

We will also change two things from tutorial 1 — ultrasoft instead of
norm-conserving, PBEsol instead of PBE — and the reasons for both are worth
having.

## What we are asking for

```bash
pseudoforge generate -e Si -t us -p psl-high -x pbesol -o ./02-silicon
```

`-t us`
: **Ultrasoft.** Norm conservation is relaxed and the missing charge is
  restored with augmentation functions. The result is much softer — a far lower
  plane-wave cutoff for the same accuracy — at the cost of a higher
  charge-density cutoff and a more involved formalism. For routine plane-wave
  work on silicon this is a reasonable choice; PAW would be another.

`-x pbesol`
: **PBEsol.** PBE is fitted to molecular data and systematically overestimates
  lattice constants of solids by around 1%. PBEsol restores the gradient
  expansion for exchange and does substantially better on lattice constants and
  bulk moduli. If your calculation is a solid and you care about geometry,
  PBEsol is often the better GGA. If you are comparing against published PBE
  numbers, use PBE.

    The important point is not which is better in the abstract — it is that
    **whichever you use in `pw.x`, the pseudopotential must have been generated
    with it.**

## What happens

```text
 project      : ./02-silicon
 profile      : PSlibrary 1.0.0 (high accuracy) (generated)
 family       : US
 functional   : PBEsol (solids) (GGA) -- generated natively by Quantum ESPRESSO ld1.x as dft=PBESOL
 relativity   : Scalar-relativistic (no spin-orbit)
 UPF format   : v2
 engine       : Quantum ESPRESSO ld1.x v.7.6 [build 7de3694ef3fd] /opt/espresso/7.6/ld1.x

 ELEM PSEUDOPOTENTIAL                    STATUS    PARAMS      TRANSFER   ECUT/RHO     NOTE
 ----------------------------------------------------------------------------------------------------
 Si   Si.pbesol-n-rrkjus_psl.1.0.0.UPF   ok        n.1.0.0     excellent  -

 1 succeeded, 0 succeeded with warnings, 0 failed, 0 skipped (1 total)

 TRANSFER measured by: ld1 iswitch=2
```

This time the `TRANSFER` column has something in it, because PSlibrary ships
test decks for its ultrasoft sets. The file name records the choices:
`Si` · `pbesol` · `n` (no semicore) · `rrkjus` (RRKJ ultrasoft) ·
`psl.1.0.0`.

## What "excellent" actually measured

The grade is not an opinion. It comes from a second `ld1.x` run, with
`iswitch=2`, which takes the pseudopotential that was just generated and
re-solves the atom in configurations it was **not** fitted to, comparing
against the all-electron answer for the same configurations.

The configurations are PSlibrary's own, not PseudoForge's invention:

```bash
grep configts ./02-silicon/tests/Si.test.in
```

```text
   configts(1)='3s2 3p2'
   configts(2)='3s2 3p1 3d0'
   configts(3)='3s2 3p0 3d0'
   configts(4)='3s1 3p3'
   configts(5)='3s1 3p2 3d0'
```

Read down that list: the neutral ground state, then progressively ionised and
excited configurations, including ones that put charge into the empty d
channel. A pseudopotential that is only correct for the configuration it was
fitted to would come apart on lines 3 to 5.

The numbers are in `tests/transferability.tsv`:

```bash
cat ./02-silicon/tests/transferability.tsv
```

```text
Si	Si.pbesol-n-rrkjus_psl.1.0.0.UPF	0.000640	0.000171	excellent	ld1 iswitch=2	re-solved in unfitted configurations
```

| Column | Value | Meaning |
|---|---|---|
| 3 | `0.000640` | largest absolute eigenvalue error over all channels and configurations, in Ry |
| 4 | `0.000171` | total-energy difference, in Ry |
| 5 | `excellent` | the grade |
| 6 | `ld1 iswitch=2` | **the method that produced it** |
| 7 | | what was done |

0.64 mRy is about 9 meV. For comparison, room temperature is 25 meV. The
pseudopotential reproduces all-electron eigenvalues, in configurations nobody
fitted it to, to well inside thermal energy.

### The grading scale

| Grade | Largest eigenvalue error |
|---|---|
| `excellent` | below 1 mRy |
| `good` | below 5 mRy |
| `marginal` | below 20 mRy |
| `poor` | 20 mRy or more |
| `no-data` | the test ran but produced no usable number |
| `-` | no test deck exists for this set, so nothing was measured |

The thresholds are in `transfer_verdict` in `lib/validate.sh`, and every engine
that reports a transferability number is graded on the same scale.

!!! warning "Column 6 is not decoration"
    Six of the nine engines can produce a transferability number, and they do
    not all measure the same thing. `ld1 iswitch=2` re-solves the atom;
    ONCVPSP reports its own configuration tests; OPIUM reports a design
    diagnostic. Comparing an `excellent` from one against a `good` from another
    is comparing two different measurements. That is why the method travels
    with the grade everywhere it is printed, including in the report footer:
    `TRANSFER measured by: ld1 iswitch=2`.

## Looking at it rather than reading a number

```bash
pseudoforge generate -e Si -t us -p psl-high -x pbesol --plot -o ./02-silicon
```

writes two plots per element into `02-silicon/plots/`:

- **log derivatives** — the all-electron and pseudo curves should lie on top of
  each other. Where they separate, the pseudopotential scatters differently
  from the real atom at that energy. A pole in one curve and not the other is a
  ghost state.
- **radial wavefunctions** — the pseudo curves must match the all-electron ones
  outside the matching radius and be smooth and nodeless inside it.

With no `gnuplot` and no `matplotlib` this prints one line saying so and exits
0; the data is still written to `tests/` so you can plot it elsewhere. See
[Plot the diagnostics](../how-to/plot.md).

## Comparing two choices

The point of a tool like this is being able to ask "what if". Generate the same
element both ways and compare:

```bash
pseudoforge generate -e Si -t us  -p psl-high -x pbesol -o ./si-us
pseudoforge generate -e Si -t paw -p psl-high -x pbesol -o ./si-paw

pseudoforge compare ./si-us/pseudos/Si.pbesol-n-rrkjus_psl.1.0.0.UPF                     ./si-paw/pseudos/Si.pbesol-n-kjpaw_psl.1.0.0.UPF
```

`pseudoforge compare` takes two **files**, not two projects, and reports what
differs between them — valence charge, the projectors, the grid, the suggested
cutoffs. Add `--ecut N` to compare them at a specific plane-wave cutoff.

## Using it

```text
ATOMIC_SPECIES
  Si  28.0855  Si.pbesol-n-rrkjus_psl.1.0.0.UPF
```

Ultrasoft needs `ecutrho` around **8×** `ecutwfc`, not the 4× that is right for
norm-conserving — the augmentation charge is sharp even when the wavefunction
is smooth. Getting this wrong is one of the most common sources of
irreproducible ultrasoft results. To measure the pair rather than assume it:

```bash
pseudoforge generate -e Si -t us -p psl-high -x pbesol --cutoff-scan -o ./02-silicon
```

which fills in the `ECUT/RHO` column that has been showing `-` so far.

---

Next: [Iron, semicore and PAW](03-iron.md) — where the core–valence partition
starts to matter.
