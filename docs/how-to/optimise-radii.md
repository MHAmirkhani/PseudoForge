# Optimise the cut-off radii

Wider cut-off radii give a softer pseudopotential — fewer plane waves — and
reproduce the all-electron atom less well away from the configuration it was
fitted to. `pseudoforge optimise` sweeps that trade for one element and picks,
by a stated rule, from measurements the tool already makes.

```bash
pseudoforge optimise -e Si -t nc -p pseudoforge-auto -x pbe --engine oncvpsp \
    --cutoff-scan --save-recipe si-soft
```

## What it does

It runs `generate` once per rung of a `--rcut-scale` ladder — each into its own
directory, so every candidate is a complete project you can inspect — and reads
back what that run measured: whether it generated, its transferability verdict
and largest eigenvalue error, and, with `--cutoff-scan`, the converged
`ecutwfc`.

Measured on Si, PBE, ONCVPSP, with `--cutoffs "12 15 18 21 24 27 30 35 40"`:

| scale | verdict | max &#124;Δε&#124; (Ry) | ecutwfc (Ry) |
|---|---|---|---|
| 0.9 | good | 0.00234 | 21 |
| 1.0 | good | 0.00173 | 18 |
| **1.1** | good | **0.00119** | **15** |
| 1.2 | good | 0.00314 | 15 |
| 1.3 | marginal | 0.00524 | 12 |

It chose **1.1**: softer than the default radii *and* more transferable. 1.2
ties it on cutoff and loses on the error; 1.3 is softer still and falls below
`good`.

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

- It works where `--rcut-scale` does: **ld1, oncvpsp, opium, ape**. Other
  engines are refused with the same reason `generate` gives.
- All radii are scaled together, so the ratio between channels is the base
  recipe's. It does not optimise channels independently.
- It does not fit a lattice constant. Transferability and cutoff are the
  criteria.
- Transferability must be measured for the engine and profile you use. Where
  it is not, every rung is `no-data` and no choice is made.
