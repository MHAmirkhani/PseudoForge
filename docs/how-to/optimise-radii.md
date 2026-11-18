# Optimise the cut-off radii

Wider cut-off radii give a softer pseudopotential — fewer plane waves — and
reproduce the all-electron atom less well away from the configuration it was
fitted to. `pseudoforge optimise` sweeps that trade for one element and picks,
by a stated rule, from measurements the tool already makes.

```bash
pseudoforge optimise -e Si -t paw -p psl-high -x pbe --engine ld1 \
    --cutoff-scan --save-recipe si-soft
```

## What it does

It runs `generate` once per rung of a `--rcut-scale` ladder — each into its own
directory, so every candidate is a complete project you can inspect — and reads
back what that run measured: whether it generated, its transferability verdict
and largest eigenvalue error, and, with `--cutoff-scan`, the converged
`ecutwfc`.

An atomic reference-configuration fit is not a transferability test. ONCVPSP
decks without alternative configurations now report `no-data`; this command
does not choose a radius from that fit alone. The earlier Si ONCVPSP example
measured a fit and is not evidence of improved transferability.
For cross-engine selection against common physical observables, use
[reference-constrained design](reference-design.md).

## The rule

1. **Eligible** means it generated (`ok` or `ok-warn`) and its transferability
   verdict is at least `--min-grade` (default `good`). `no-data` is never
   eligible — a choice made without measuring transferability is a guess.
2. **With a cutoff scan**, the lowest converged `ecutwfc` wins; ties go to the
   better verdict, then the smaller eigenvalue error, then the larger scale.
3. **Without one**, the largest eligible scale wins — the softest construction
   that still passes.

If only some candidates have a measured cutoff, cutoffs are not compared at
all: ranking a measurement against its absence is not a ranking.

## Options

| option | default | |
|---|---|---|
| `-e EL` | — | one element; radii are chosen per element |
| `--scales LIST` | `0.85,0.90,0.95,1.00,1.05,1.10,1.20,1.30` | the ladder |
| `--min-grade G` | `good` | `excellent`, `good`, `marginal` or `poor` |
| `--save-recipe NAME` | — | save the winner; `generate --recipe NAME` reproduces it |
| `-o DIR` | `./optimise-EL` | one `rc-<scale>/` project per rung, plus `optimise.tsv` and `choice` |

Everything else is passed to `generate` unchanged — family, functional,
profile, engine, `--cutoff-scan`, `--cutoffs`.

A cutoff ladder that starts above where the pseudopotential converges tells
you nothing about softness: every rung will report the lowest value. Start low.

## Limits, stated so they are not assumed

- Radius mapping exists for eight engines (GTH needs `--refit`); fhi98PP
  requires explicit channel radii instead. Selection additionally needs a
  measured transferability grade. Radius support alone therefore does not
  make every engine eligible for this command. Inspect `physics ENGINE` and
  the [manual-input workflow](manual-generation.md).
- All radii are scaled together, so the ratio between channels is the base
  recipe's. It does not optimise channels independently.
- It does not fit a lattice constant. Transferability and cutoff are the
  criteria.
- Transferability must be measured for the engine and profile you use. Where
  it is not, every rung is `no-data` and no choice is made.

Output directories must be new or empty. Previous projects are never deleted.
