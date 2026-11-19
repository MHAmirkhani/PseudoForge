# PseudoForge Evidence Status and Scientific Ledger

**Document status**: Frozen for v1.4.0 development  
**Baseline date**: 2026-11-19  
**Reference commit**: `a120dc9a0ec82daf8ff1534bec26ce094fb5ccf0`  
**Evidence root**: `/home/mammadzi/.codex/visualizations/2026/11/11/01a1ca5d-75d2-7eb3-bbc3-60e0b6ccaa8b/`

---

## 1. Subsystem Evidence Matrix (All Nine Engines)

Claims regarding pseudopotential quality and validation are strictly categorized by the **L1–L6 Evidence Ladder**:

- **L1 (Native Generation)**: Atomic executable successfully executes and generates native output files.
- **L2 (Valid Serialization)**: Output conforms strictly to expected file specification (UPF v2, PSP8, PAW-XML, GTH, VPS) without syntax or numerical corruption.
- **L3 (Consumer SCF Convergence)**: Compatible electronic-structure solver reads file and reaches self-consistent field (SCF) ground state without numerical breakdown.
- **L4 (Atomic Diagnostics)**: Solver verifies logarithmic derivatives, absence of bound/unbound ghost states, and core-valence eigenvalues against all-electron atomic reference.
- **L5 (Material Accuracy)**: Candidate achieves relative energy, force, or stress targets against an independent all-electron solid-state or molecular reference.
- **L6 (Independent Transferability)**: Candidate demonstrates physical accuracy on a fresh, previously unexamined chemical or structural family under identical settings.

### Engine Evidence Table

| Engine | L1 (Generation) | L2 (Serialization) | L3 (Consumer SCF) | L4 (Atomic Diag.) | L5 (Material Accuracy) | L6 (Fresh Holdout) |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **`ld1`** | **Verified** | **Verified** (UPF v2) | **Verified** (QE 7.6 `pw.x`) | **Verified** | **Verified** (Si diamond FLEUR/WIEN2k AE EOS, 0.298 meV/atom) | **Empty** |
| **`oncvpsp`** | **Verified** | **Verified** (UPF v2) | **Verified** (QE 7.6 `pw.x`) | **Verified** | **Verified** (Si diamond FLEUR/WIEN2k AE EOS, 1.886→1.265 meV/atom) | **Empty** |
| **`uspp`** | **Verified** | **Verified** (UPF v2 via `upfconv.x`) | **Verified** (QE 7.6 `pw.x`) | **Verified** | **Verified** (Si diamond FLEUR/WIEN2k AE EOS, 0.784→0.766 meV/atom) | **Empty** |
| **`fhi98pp`** | **Verified** | **Verified** (CPI / ABINIT PSP6) | **Verified** (ABINIT 9.6.2) | **Verified** | **None** (No independent PW92 all-electron reference) | **Empty** |
| **`opium`** | **Verified** | **Verified** (UPF v2) | **Verified** (QE 7.6 `pw.x`) | **Verified** | **Failed** (Si diamond error >33 meV/atom; exceeded 2 meV/atom gate) | **Empty** |
| **`gth`** | **Verified** | **Verified** (GTH analytic) | **Verified** (CP2K 2025.2) | **Verified** | **Failed** (Drift >10 meV/atom on k-mesh; rejected by selection gate) | **Empty** |
| **`atompaw`** | **Verified** | **Verified** (UPF, PAW-XML) | **Verified** (QE 7.6 `pw.x`) | **Verified** | **Verified** (Si diamond FLEUR/WIEN2k AE EOS, 1.844 vs 1.854 meV/atom) | **Empty** |
| **`ape`** | **Verified** | **Verified** (UPF v2) | **Verified** (QE 7.6 `pw.x`) | **Verified** | **Failed** (Stock Si ghost; fixed local-s reached 6.73 meV/atom, >2 meV/atom gate) | **Empty** |
| **`adpack`** | **Verified** | **Verified** (OpenMX `.vps`) | **Verified** (OpenMX 4.0.1) | **Verified** | **None** (Isolated He atom test only; no solid-state material reference) | **Empty** |

---

## 2. Evidence File and Report Registry

Every cell in the matrix is supported by immutable archived records with verified SHA-256 digests:

1. **`ld1`**:
   - L1/L4: `all-engine-manual-physics/ld1-manual/reports/summary.txt`
   - L2/L3: `v14-nine-engine-optimization/native-all-engines.json`
   - L5: `v14-nine-engine-optimization/qe-silicon-results.csv`, `v14-checkpoint-and-force-pilot/reports/equal-budget-results.json`
2. **`oncvpsp`**:
   - L1/L4: `all-engine-manual-physics/oncvpsp-manual/reports/summary.txt`
   - L2/L3: `v14-nine-engine-optimization/native-all-engines.json`
   - L5: `v14-nine-engine-optimization/qe-silicon-results.csv`, `v14-convergence-and-engine/si-convergence.tsv`
3. **`uspp`**:
   - L1/L4: `all-engine-manual-physics/uspp-manual/reports/summary.txt`
   - L2: Delimiter-corrected UPF serialization verified in `v14-nine-engine-optimization/native-all-engines.json` (commit `70514d0`)
   - L3/L5: `v14-nine-engine-optimization/qe-silicon-results.csv`
4. **`fhi98pp`**:
   - L1/L4: Native `pslp.x` ghost analysis and s-channel RMS arctangent discrepancy (0.0101 rad) in `v14-nine-engine-optimization/native-all-engines.json`
   - L2/L3: ABINIT format-6 replay in `v14-nine-engine-optimization/reports/abinit-fhi98pp-dense.json`
5. **`opium`**:
   - L1/L4: `all-engine-manual-physics/opium-manual/reports/summary.txt`
   - L2/L3: `v14-nine-engine-optimization/native-all-engines.json`
   - L5: Exceeded tolerance in `v14-nine-engine-optimization/qe-silicon-results.csv`
6. **`gth`**:
   - L1/L4: Refit residual table in `v14-nine-engine-optimization/native-all-engines.json`
   - L2/L3: 30 CP2K calculations in `v14-nine-engine-optimization/reports/cp2k-gth-ladder.json`
   - L5: Retrospective training gate rejection in `v14-checkpoint-and-force-pilot/reports/cp2k-training-gate.json`
7. **`atompaw`**:
   - L1/L4: `all-engine-manual-physics/atompaw-manual/reports/summary.txt`
   - L2/L3: `v14-nine-engine-optimization/native-all-engines.json`
   - L5: `v14-nine-engine-optimization/qe-silicon-results.csv`
8. **`ape`**:
   - L1/L4: Ghost detection on stock and radius variants in `all-engine-manual-physics/ape-manual/reports/summary.txt`
   - L2/L3: Real QE execution on fixed local-s in `v14-nine-engine-optimization/native-all-engines.json`
   - L5: Sweep in `v14-nine-engine-optimization/qe-silicon-results.csv`
9. **`adpack`**:
   - L1/L4: Patched source execution and logarithmic-derivative metric in `v14-convergence-and-engine/` and `native-all-engines.json`
   - L2/L3: He VPS evaluation in `v14-nine-engine-optimization/reports/openmx-adpack.json`

---

## 3. Negative Results and Identified Failure Modes

To ensure scientific integrity, failed experiments and negative results are preserved as explicit evidence:

1. **Molecular Force Cutoff Gate Failure (Silanone Holdout)**:
   - *Report*: `v14-checkpoint-and-force-pilot/reports/molecular-force-summary.json`
   - *Result*: In silane training, SG15 Si radius ×1.03 was selected. On held-out silanone in 18 and 22 bohr boxes, the maximum force component error against PySCF all-electron reference was 0.00278 and 0.00299 Ry/bohr (passing the 0.008 Ry/bohr reference tolerance). However, the 50 → 65 Ry cutoff drift was **0.00256 and 0.00264 Ry/bohr**, exceeding the 0.002 Ry/bohr numerical tolerance. **Both original held-out tests failed**.
   - *Lesson*: A post-hoc test at 80 Ry reduced drift to 0.00044 Ry/bohr, but operates on an already-examined geometry. It is classified as calibration guidance, not holdout validation.
2. **CP2K/GTH Ranking Inversion under Ladder Refinement**:
   - *Report*: `v14-checkpoint-and-force-pilot/reports/cp2k-training-gate.json`
   - *Result*: In the 5-level CP2K ladder (grid cutoff, relative cutoff, Gaussian basis, k-mesh), tightening the k-mesh from 2³ to 3³ moved energy differences by ~10 meV/atom and inverted candidate rankings. The retrospective CP2K selection gate rejected **all three archived training candidates**. CP2K has no stable GTH winner.
3. **Ti/O Factorial Multi-Element Null Interaction**:
   - *Report*: `v14-checkpoint-and-force-pilot/reports/ti-o-factorial-tight.json`
   - *Result*: A 4-way factorial swap on TiO rocksalt and TiO₂ fluorite yielded signed interactions of **+0.001020 meV/atom** and **−0.000454 meV/atom**. These values are orders of magnitude smaller than numerical convergence drift, and opposite substitutions were favored in the two structures (rocksalt: baseline Ti / tuned O; fluorite: tuned Ti / baseline O). There is no measurable synergistic multi-element coupling.
4. **OPIUM Transferability Tolerance Failure**:
   - *Report*: `v14-nine-engine-optimization/qe-silicon-results.csv`
   - *Result*: Radius sweeps reached 34.162 meV/atom (default) and 33.516 meV/atom (tuned) against the all-electron Si EOS, failing the 2.0 meV/atom tolerance.
5. **APE Unphysical Ghost States**:
   - *Report*: `all-engine-manual-physics/` and `native-all-engines.json`
   - *Result*: Stock and radius-only Si inputs triggered bound ghost state warnings. Fixing the local channel to s allowed SCF completion, but error remained at 6.73 meV/atom (>2 meV/atom gate).
6. **AtomPAW Semicore Metallic Failure**:
   - *Report*: `v14-convergence-and-engine/`
   - *Result*: Ti 12-valence-electron semicore intervention (promoting 3s/3p) successfully generated valid PAW datasets but failed the metallic BCC/FCC training gate.
7. **TiO₂ Fluorite Hydrostatic Pressure Cutoff Drift**:
   - *Report*: `v14-convergence-and-engine/`
   - *Result*: Derivative of the all-electron EOS exhibited extreme plane-wave cutoff sensitivity: equilibrium pressure shifted from −560.58 kbar at 50 Ry to −195.58 kbar at 60 Ry (4³ mesh).
8. **Equal-Budget Search Strategy Equivalence**:
   - *Report*: `v14-checkpoint-and-force-pilot/reports/equal-budget-results.json`
   - *Result*: Across 8 real QE runs at seeds 37 and 73 under 0.025 core-hour limits, random, uniform, adaptive UCB, and Bayesian GP-UCB all selected `ld1-us-radius-0.97` (seed 37) and `ld1-us-radius-1.03` (seed 73). On this same-family volume split, adaptive search provided no measurable advantage over random allocation.

---

## 4. Budget Semantics and Resource Accounting

- All search budgets (`training_core_hours`) are defined strictly as:
  > **`training_core_hours` is single-logical-CPU active training wall time enforced by CPU affinity. It is not a scheduler reservation; cluster-accounting adapters are future work.**
- Linux task affinity (`sched_setaffinity`) pins the execution to one logical CPU.
- Child processes are monitored via `getrusage(RUSAGE_CHILDREN)`; setup time, active training time, interrupted attempts, and held-out evaluations are isolated and recorded separately in `report.json`.

---

## 5. Holdout Ledger (Permanently Calibration-Only)

Under strict pre-registration rules, **any geometry or chemical system evaluated during method exploration, failure diagnosis, or parameter tuning is permanently retired to the calibration set**. The following materials are permanently ineligible for L6 holdout claims:

1. **Silicon Diamond EOS** (volumes 0.96, 0.98, 1.02, 1.04 $\times V_0$).
2. **Titanium Metallic Phases** (BCC and FCC equilibrium and compressed).
3. **Titanium Oxides** (rocksalt TiO and fluorite TiO₂).
4. **Silane ($SiH_4$)** (displaced molecular training geometry).
5. **Silanone ($H_2SiO$)** (displaced molecular holdout geometry evaluated in pilot and diagnosis).

All future L6 claims must evaluate completely fresh chemical families (e.g. Ge diamond, binary carbides, III-V semiconductors) with independently verified reference datasets.
