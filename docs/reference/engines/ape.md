# APE — Atomic Pseudopotential Engine

Norm-conserving generation backed by libxc, which gives it a far wider
functional range than the engines with built-in functional tables.

| | |
|---|---|
| **Families** | NC |
| **Relativity** | non-relativistic, scalar |
| **Functionals** | whatever libxc provides — by far the widest range here |
| **Native output** | UPF, directly |
| **Licence** | GPL-2.0-or-later |
| **Upstream** | <https://gitlab.com/ape/ape> |

!!! warning "Not in the pre-built store"
    APE is documented here because it is an engine PseudoForge drives and
    builds, and because the measurements below are worth having on record.
    It is **not** in the pre-built native store
    (`~/pf-native/ape/` does not exist), for two reasons:

    * its GGA path has no solution for an open d shell (Ti, Fe, Cu, Zn, Ag
      all fail — see *Known limitation* below);
    * for the functional range that does work (LDA), `ld1` already
      covers every element and the store is not made larger for no new
      coverage.

    Run `pseudoforge engines build ape` and use it locally if a
    functional libxc carries and no other engine does is what you need.

## Installing

```bash
pseudoforge engines build ape
```

APE needs both **libxc** and **GSL**; PseudoForge builds them into its own
prefix first if they are not already present.

## Use it for

A functional no other engine here supports. If libxc has it, APE can generate
with it, and the file carries that functional rather than a proxy.

```bash
pseudoforge generate -e Si -t nc -p pseudoforge-auto -x revpbe --engine ape -o ./out
```

## Known limitation: d-shell elements

**Five elements do not generate.** Measured 2026-09-17, `-x pbe`, under both
`pseudoforge-auto` and `psl-high`:

| | |
|---|---|
| pass | Br, Au |
| fail | Ti, Fe, Cu, Zn (`State: 3d is unbound`), Ag (`State: 4d is unbound`) |

All five generate normally with `-x pz`. The failure is the functional, not the
element: APE has no working GGA path for an open d shell, and its own shipped
chromium test fails the same way when only the functional is changed. See
[the roadmap](../../contributing/roadmap.md#31-ape-no-gga-path-for-open-d-transition-metals-cause-established-upstream).

An *occupied* d shell is driven unbound during the SCF. The cause is not
established. Use [`ld1`](ld1.md) or [`oncvpsp`](oncvpsp.md) for these elements.

`tests/test_ape_live.sh` runs the engine and holds this record, so the status
and the measurement are the same thing.

!!! warning "This was previously reported as solved"
    `tests/test_ape.sh` checks **deck construction** and runs without APE
    installed — it says so in its own header. Its passing checks say the deck
    is built correctly; they never said APE accepts it.

### The bromine fallback, and why it does not help here

A separate failure — `multiroot_solve_system` with a d shell pseudised — is
handled by an auto-fix retry:

| Failure | Attempt 1 |
|---|---|
| TM construction fails with a d shell pseudised | retry with that d shell as core |

For bromine, whose 3d¹⁰ is deep semicore, treating it as core is the textbook
choice for a halogen anyway — so the retry lands on the answer a careful person
would have chosen.

That fallback keys on `multiroot_solve_system` and **does not fire** for the
five above: their state records `attempts: 0`, because an unbound state is a
different failure. Widening the trigger to catch both would change which shell
is pseudised for elements that never asked for it — a physics change, and not
one to make on a guess.

!!! note "Why a retry rather than a rule"
    Zinc has the same 3d¹⁰/4s² shape and builds correctly with its d
    pseudised. A blanket "filled d below valence → core" rule would have
    changed zinc's answer for no reason. Because the fallback fires only on an
    observed failure, zinc never reaches it.

### What the failure was actually about

Two initial diagnoses were wrong and are worth recording, because they are the
kind of plausible story that survives unless measured:

- *"d channels need a much smaller cutoff radius."* Measured against SG15, the
  d/s radius ratio is 0.89–1.06. It does not.
- The real causes were the **l-gap** between the channels being pseudised, and
  using **one radius for all channels** where the construction needed per-channel
  values.

## What PseudoForge does to APE's output, and why

APE's UPF is not usable by Quantum ESPRESSO as APE writes it. Each step below
was found by running `pw.x` on the file, not by the validator, which passed
all three:

1. **The functional is written in.** APE leaves the v1 functional field blank —
   it runs the functional through libxc and has no QE name for it — and pw.x
   stops with `unrecognized dft`. For LDA and GGA the deck's functional is
   written in (`PBE`, `LDA`, …). For meta-GGA it is not: QE's name there is
   ld1's proxy parent, and writing `PBE` into a SCAN file would mislabel it.
2. **The file is rewritten as UPF v2.** QE 7.6 misreads APE's v1 layout: one Si
   pseudopotential gives 645 kbar read as v1 and 46 kbar read as v2, where
   ONCVPSP gives 25. The rewrite goes through upfconv.x and changes no number.
3. **APE's own ghost report is acted on.** APE runs the Gonze–Stumpf–Scheffler
   test and logs `Ghost state found`. On that line, each pseudised channel is
   tried as the local one (`LLocal`) and the first APE itself reports clean is
   taken; the note on the result says which. For Si PBE this is the s
   channel, and bulk Si then comes out at −15.761 Ry against ONCVPSP's
   −15.763. If every channel ghosts, the element fails.

APE's constructions for d metals can be **hard**: its Cu LDA needs about
200 Ry for the stress to converge (−4,781 kbar at 60 Ry, +29.6 at 200). Run
`--cutoff-scan` before trusting a cutoff; the file itself states none.

## Citation

> M. J. T. Oliveira and F. Nogueira, "Generating relativistic pseudo-potentials
> with explicit incorporation of semi-core states using APE, the Atomic
> Pseudo-potentials Engine", *Computer Physics Communications* **178**, 524
> (2008).
> DOI: [10.1016/j.cpc.2007.11.003](https://doi.org/10.1016/j.cpc.2007.11.003)

From the **"How to cite APE"** section of `README.md` in the APE source tree —
the authors state it themselves.

---

## On the API

This engine as the server reports it, including whether its binary is
present there:

```bash
curl -s https://pseudo.amirkhani.me/api/engines/ape
pseudoforge api GET /api/engines/ape          # the same thing, locally
```

See the [HTTP API reference](../http-api.md). On the public server
`available` is `false` for every engine -- it does not have them, and
[that is the architecture](../../architecture/http.md).

## See also

- [Limitations](../limitations.md#ape-no-gga-path-for-open-d-transition-metals) — the d-shell failure, and why APE is not in the store
- [Upstream](../upstream.md#ape-gga-path-fails-for-open-d-transition-metals) — why this is documented and not reported
