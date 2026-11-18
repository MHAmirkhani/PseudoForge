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
