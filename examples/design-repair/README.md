# Cross-Engine Repair Demonstration: Silicon Diamond

This directory provides a self-contained three-way comparative benchmark evaluating automated pseudopotential repair strategies for Silicon in the diamond structure against the independent all-electron FLEUR/WIEN2k reference from the ACWF project (Bosoni et al., *Nature Reviews Physics* 5, 2023).

---

## 1. Overview of Comparative Arms

| Arm | Engine | Strategy | Parameter Controls | Physics Mechanism |
| :--- | :--- | :--- | :--- | :--- |
| **Baseline** | APE | Unrepaired | Default configuration (no explicit local channel) | Bound ghost state develops in the $s$-channel due to default projector placement |
| **Single-Engine** | APE | `single_engine_repair` | `LLocal = 0` ($s$-channel local) with native Troullier–Martins radii ($r_c = 2.38, 3.56$ bohr) | Eliminates bound ghost state by shifting local component to $s$; reduces EOS drift from 19.03 to 6.73 meV/atom |
| **Cross-Engine** | APE | `cross_engine_repair` | Parameters imported from donor `oncvpsp`: `LLocal = 0`, $r_c(s) = 1.60$, $r_c(p) = 1.71$ bohr | Adopts proven projector and matching radii from Hamann norm-conserving formulation, achieving sub-2 meV/atom material accuracy |

---

## 2. Evidence Ladder (L1–L5)

Every candidate is evaluated across the formal PseudoForge evidence hierarchy:
- **L1 (Native Generation)**: Generator binary execution, clean exit (code 0), artifact generation time.
- **L2 (Serialization)**: Valid UPF v2 schema syntax and metadata integrity.
- **L3 (Consumer SCF)**: Self-consistent field convergence in Quantum ESPRESSO (`pw.x`).
- **L4 (Atomic Diagnostics)**: Absence of unphysical ghost states in bound and scattering spectra.
- **L5 (Material Accuracy)**: Equation of state Birch–Murnaghan fit and relative energy error vs all-electron FLEUR/WIEN2k reference across volume expansions/compressions ($V/V_0 \in [0.96, 1.04]$).

> [!IMPORTANT]
> **Budget Semantics**: `training_core_hours` is single-logical-CPU active training wall time enforced by CPU affinity. It is not a scheduler reservation; cluster-accounting adapters are future work.

---

## 3. Running the Demonstration

To run the full three-way comparison:
```bash
python3 run.py -o results
```

Options:
- `-o, --output DIR`: Destination directory for repaired inputs, generated pseudopotentials, SCF logs, and reports (default: `results`).
- `--pw PATH`: Path to Quantum ESPRESSO `pw.x` executable (defaults to `PW_BIN` or `~/.pseudoforge/bin/pw.x`).
- `--skip-qe`: Run generation and atomic diagnostics, using benchmark archive for L5 material accuracy.

Artifacts emitted:
- `results/results.json`: Full machine-readable record of parameters, generation timings, and L1–L5 gate outcomes.
- `results/comparison_summary.md`: Summary table comparing the three arms.
