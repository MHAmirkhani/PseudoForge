# Validate a pseudopotential

A file that exists is not a result. PseudoForge runs three different checks,
they answer three different questions, and only the first is automatic.

## 1. Structural — is it a well-formed file?

Runs on every generation, and available on its own for files you did not make:

```bash
pseudoforge validate Si.pbe-n-kjpaw_psl.1.0.0.UPF
pseudoforge validate ~/pseudos/*.UPF
```

This reads the file and checks it is internally consistent: the header parses,
`z_valence` is positive and plausible for the element, the grid is monotonic,
the projector count matches the declared `l_max`, the augmentation block is
present if the file claims to be ultrasoft or PAW.

It is what caught caesium:

```text
ERROR: implausible z_valence=-5.0000000000000000
```

`ld1.x` wrote that file successfully and exited 0. Nothing in the engine
objected. The check exists because the engine will not make it for you.

## 2. Transferability — is it right for atoms it was not fitted to?

The real question. A pseudopotential is fitted to one reference configuration;
it is useful only if it stays correct in the configurations your solid actually
visits.

Runs automatically after generation when the library ships test decks:

```text
== Transferability tests (ld1.x, iswitch=2) ==

 Si   Si.pbesol-n-rrkjus_psl.1.0.0.UPF   ok        n.1.0.0     excellent  -
```

The detail is in `tests/transferability.tsv`:

```text
Si	Si.pbesol-...UPF	0.000640	0.000171	excellent	ld1 iswitch=2	re-solved in unfitted configurations
```

| Column | Meaning |
|---|---|
| 3 | largest absolute eigenvalue error, Ry |
| 4 | total-energy difference, Ry |
| 5 | grade |
| 6 | **the method that produced it** |
| 7 | what was done |

### The grades

| Grade | Largest eigenvalue error |
|---|---|
| `excellent` | below 1 mRy |
| `good` | below 5 mRy |
| `marginal` | below 20 mRy |
| `poor` | 20 mRy or more |
| `no-data` | the test ran but produced no usable number |
| `-` | no test deck exists for this set |

For scale: 1 mRy is 13.6 meV, and room temperature is 25 meV.

### Column 6 is not decoration

Six engines can report a transferability number and they do not measure the
same thing:

| Method | What it does |
|---|---|
| `ld1 iswitch=2` | re-solves the atom in the library's unfitted configurations |
| ONCVPSP's own tests | the configuration tests ONCVPSP runs internally |
| `atompaw leakage/overlap` | log-derivative agreement and charge leakage |
| OPIUM design diagnostics | the design-quality figures OPIUM reports |

An `excellent` from one is not comparable with a `good` from another. That is
why the method travels with the grade everywhere, including the report footer:
`TRANSFER measured by: ld1 iswitch=2`.

### An empty column is an answer

`-` means no test deck exists — PSlibrary ships them for its PAW and ultrasoft
sets and not for norm-conserving, so a norm-conserving PSlibrary run has
nothing to be tested against. Inventing five configurations and grading against
those would produce a number about PseudoForge's guesses rather than the
library's judgement. See
[Tutorial 1](../tutorials/01-carbon.md#why-the-transferability-column-is-empty).

## 3. Cutoff convergence — how expensive is it?

Off by default, because it runs `pw.x` several times per element and is far
slower than the generation:

```bash
pseudoforge generate -e Si -t paw -p psl-high -x pbe --cutoff-scan -o ./out
```

```bash
pseudoforge generate ... --cutoff-scan --cutoffs "30 40 50 60 70 80" --cutoff-tol 0.5
```

`--cutoff-tol` is the total-energy convergence target in mRy/atom; the
reported cutoff is where the energy stops moving by more than that. The result
fills the `ECUT/RHO` column and is recorded in the report.

The `rho` half matters as much as the `wfc` half:

| Family | `ecutrho`/`ecutwfc` |
|---|---|
| norm-conserving | 4 |
| ultrasoft | 8 |
| PAW | 8 |

Using 4 with an ultrasoft pseudopotential is one of the most common causes of
irreproducible results — the augmentation charge is sharp even when the
wavefunction is smooth.

## Ghost states

A ghost is a spurious bound state introduced by the separable
Kleinman–Bylander form: an eigenvalue the real atom does not have. PseudoForge
reports them when the engine does:

```text
 Au   Au.rel-pbe-oncv.UPF   ok   library   no-data   -   positive-energy ghost above ~39.13 Ry (informational; common in published tables)
```

**Where the ghost is decides whether it matters.** Below or near the valence
energies it is fatal — it will appear in your band structure as a band that
should not exist. Tens of Ry above the valence region, as here, it is common in
published tables and is labelled informational rather than treated as a
failure.

To judge for yourself, plot the log derivatives:

```bash
pseudoforge plot ./out
```

A ghost is a pole in the pseudo curve with no counterpart in the all-electron
curve. See [Plot the diagnostics](plot.md).

## Validating files you did not generate

```bash
pseudoforge import ./downloaded-pseudos -o ./audit
```

registers third-party files into a project, reads their headers, and runs the
structural and — where a matching test deck exists — transferability checks
against them. Use it before mixing an inherited directory into a calculation:
the usual failure is not a broken file but an inconsistent set, where two
elements were generated with different functionals.

## The final check is your own

None of the above tells you the pseudopotential is right for *your* system. The
standard practice, and there is no substitute:

1. Converge the cutoff on your actual structure.
2. Reproduce a known property — lattice constant, bulk modulus, a formation
   energy — and compare against experiment or an all-electron result.
3. Only then trust it for the property you actually want.

PseudoForge gets you to the point where step 1 is worth starting.
