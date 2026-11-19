# Paired silicon EOS pilot

This example uses three native generation paths in the existing QE design runner. It compares the unchanged PseudoForge profile with a two-point matching-radius scan for each path. Each arm keeps the generator, formalism, profile, PBE, scalar relativity, structures and QE numerical settings fixed. The tested pairs are ONCVPSP/SG15 NC, QE `ld1.x`/PSlibrary high US, and AtomPAW PAW. The tuned run selects a radius using training data and evaluates only that selection on the other volumes.

The independent reference is the Si diamond EOS fit averaged from the FLEUR and WIEN2k all-electron calculations in [Bosoni et al.](https://doi.org/10.1038/s42254-023-00655-3). The example reconstructs relative energies from the third-order Birch–Murnaghan fit and checks them in a two-atom primitive cell. It uses the pinned unary JSON published in the [Materials Cloud data package](https://archive.materialscloud.org/records/yf0rj-w3r97). The QE calculations use nonmagnetic PBE and Fermi–Dirac smearing at 0.0045 Ry. The default mesh is Γ-centered with a maximum spacing of 0.06 Å⁻¹ in each reciprocal direction, following the reference protocol.

From the repository root, with `pw.x` and the three generators installed:

```sh
work=$(mktemp -d)
source=https://raw.githubusercontent.com/aiidateam/acwf-verification-scripts/83837daf4532b3bfdc03bceaa28a649d698f62d2/acwf_paper_plots/code-data/results-unaries-verification-PBE-v1-AE-average.json
curl -fLsS "$source" -o "$work/reference.json"
python3 examples/design-si-eos/make_protocols.py "$work/reference.json" -o "$work/protocols"
for arm in oncv-nc ld1-us atompaw-paw; do
  for mode in default tuned; do
    ./pseudoforge design "$work/protocols/$arm-$mode.json" --pw /absolute/path/to/pw.x -o "$work/$arm-$mode"
  done
done
```

The preparer checks the reference checksum. An exit status of 2 from `design` means no candidate met the reported constraints. Inspect `report.json`, the executed QE inputs and the generation/SCF logs for each case. The held-out cases are other volumes of the same structural family. They exercise the selection boundary in the runner. The example uses fixed cutoffs (60 Ry wavefunction, 480 Ry density), one timing repeat and an exploratory 2 meV/atom relative-energy tolerance. Consumer cutoff convergence, runtime savings, transferability across material families and forces/stresses need separate tests. Use `--k-mesh 8` with the preparer for a shortened integration smoke run and report the reduced sampling with its results.

To measure stability at the fixed settings, add `--k-mesh 8 --convergence-mesh 12`.
This checks 80 Ry wavefunction cutoff, then 640 Ry density cutoff, then a
`12×12×12` mesh, allowing up to 0.2 meV/atom of energy-difference drift from
the base and each preceding level. It selects by training error among feasible
candidates and records changes in each stage separately. Increase and justify
the settings for production benchmarks.

## Train on metallic Ti and test on oxides

Use the same repository root and pinned data commit as above. The pilot takes
BCC and FCC titanium at equilibrium and 6% compression as training data. The
held-out structures are the rocksalt TiO and fluorite TiO2 reference prototypes
at the same volume fractions. Each comparison uses a separate energy zero
within its structure. The oxygen UPF is fixed in every candidate.

```sh
curl -fLsS "${source%/*}/results-oxides-verification-PBE-v1-AE-average.json" -o "$work/oxides.json"
./pseudoforge generate -e O -x pbe -r scalar -t nc -p sg15 --engine oncvpsp --format upf --source local --no-autofix -j 1 -o "$work/oxygen"
python3 examples/design-si-eos/make_ti_protocols.py "$work/reference.json" "$work/oxides.json" \
  "$work/oxygen/pseudos/O.pbe-oncv.UPF" --k-mesh 8 --convergence-mesh 12 -o "$work/ti-protocols"
for arm in oncv-nc ld1-us atompaw-paw; do
  for mode in default tuned; do
    ./pseudoforge design "$work/ti-protocols/$arm-$mode.json" --pw /absolute/path/to/pw.x -o "$work/ti-$arm-$mode"
  done
done
```

The Ti example uses an exploratory 5 meV/atom tolerance and a 1 meV/atom
numerical drift allowance. It tests EOS energy differences only. The two
oxides are cubic verification prototypes from the published dataset.
For a hydrostatic stress check, add `--stress-tolerance-kbar 20` (or a
justified tolerance) to the preparer. The diagonal reference components are
the pressure from the analytical negative volume derivative of the
all-electron Birch–Murnaghan fit. The off-diagonals vanish by symmetry.
These are EOS-derived hydrostatic values. An independent force benchmark
needs displacements and all-electron force observations.

To test an explicit physical intervention, generate the protocols with
`--atompaw-semicore` and run `atompaw-paw-semicore.json` as a separate design
under the same numerical settings. This trial adds Ti 3s and 3p to the
valence and scans three radii. Compare it with the radius-only arms. The
combined intervention changes two ingredients in the construction, so a
matched factorial study is needed to attribute an improvement to either one.
