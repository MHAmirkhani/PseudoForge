# Matched native engine trials

Run from the repository root to use the installed engine paths in the
PseudoForge configuration:

```sh
work=$(mktemp -d)
python3 examples/engine-pairs/run.py -o "$work/native" --jobs 3
```

The run attempts a baseline and two controlled variants per generator. Each
arm preserves its starting element, profile, functional, relativity and format.
GTH uses an 80-cycle refit for all three trials. Its weight changes alter the
fit objective, so use unweighted residuals or a common material test to
compare candidates. ADPACK records its native integrated logarithmic-derivative
error for He using the same energy window. For fhi98PP it reports the RMS
difference between arctangents of the all-electron and separable logarithmic
derivatives, modulo pi, over −0.5 to 0.5 Ha at the same diagnostic radius.
This describes the atomic boundary condition for the evaluated channel.
The native report retains the
binary and output digests, generation status and engine-specific diagnostics.
A generation error remains visible even when another trial in the arm works.
Elapsed generation times from parallel arms are descriptive.

## Evaluate compatible silicon UPFs

Prepare the Si EOS input as described in the sibling `design-si-eos` example.
For example, use the pinned unary reference with `--k-mesh 8 --convergence-mesh 12`.
Once the native trial report exists:

```sh
python3 examples/engine-pairs/evaluate_qe.py "$work/native/report.json" \
  "$work/si/oncv-nc-default.json" --pw /absolute/path/to/pw.x -o "$work/qe"
```

The evaluator filters for scalar-PBE Si UPFs. It selects a tuned candidate
using training error among numerically stable, feasible variants, then checks
the locked candidate and feasible baseline on the other Si diamond volumes.
The reference is the fitted all-electron EOS. The split is by volume within
one family. These runs measure neither force and stress transferability nor
the minimum converged production cutoff.

## Check GTH with CP2K

Use CP2K's own `BASIS_MOLOPT_UZH` file. Each fitted GTH block is copied exactly
and identified by its checksum. The default ladder increases the plane-wave
grid cutoff, relative cutoff, Gaussian basis and k mesh in separate steps.

```sh
python3 examples/engine-pairs/evaluate_cp2k.py "$work/native/report.json" \
  "$work/si/oncv-nc-default.json" --cp2k /absolute/path/to/cp2k \
  --basis /absolute/path/to/BASIS_MOLOPT_UZH --smoke -o "$work/cp2k"
```

The smoke mode runs only the first level. Both modes report the two training
volumes and leave selection to a later standalone validation. The CP2K grid
cutoff and QE wavefunction cutoff describe different numerical settings.

## Check ADPACK VPS files with OpenMX

```sh
python3 examples/engine-pairs/evaluate_openmx.py "$work/native/report.json" \
  --openmx /absolute/path/to/openmx --pao-dir /path/to/DFT_DATA19/PAO -o "$work/openmx"
```

The OpenMX test loads the three generated He VPS files and uses the same
He8.0 basis at two integration cutoffs, then repeats with He10.0. It records
the original VPS and basis checksums, SCF outcome and isolated-atom energies.
Use the output to compare numerical sensitivity and verify native consumption.
A material transferability comparison needs a separately converged reference
and a basis appropriate to that system.

## Measure a Ti/O interaction

After running the Ti example with grouped oxide cases, supply the default and
modified UPFs for each species. Keep the same diagnostic settings in all four
runs.

```sh
python3 examples/engine-pairs/swap_qe.py "$work/ti-protocols/oncv-nc-default.json" \
  --ti-default "$work/Ti-baseline.UPF" --ti-tuned "$work/Ti-tuned.UPF" \
  --o-default "$work/O-baseline.UPF" --o-tuned "$work/O-tuned.UPF" \
  --pw /absolute/path/to/pw.x --jobs 4 -o "$work/ti-o-swaps"
```

The interaction is the signed relative energy of the combined swap minus
the two individual swaps plus the baseline. It is reported at the tightest
settings when all four runs meet the declared numerical stability criterion.
This experiment diagnoses already examined materials. A joint search must
choose the pair on separate training structures before evaluating a fresh
material family.
