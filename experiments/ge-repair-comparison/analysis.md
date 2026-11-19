# Cross-Engine Pseudopotential Repair on Germanium Diamond: Empirical Validation & Transferability Analysis

## 1. Executive Summary & Scientific Verdict

This experiment reports the preregistered evaluation of **cross-engine pseudopotential repair** on a fresh elemental family: **Germanium diamond ($Fd\bar3m$)**.
All calculations were preregistered under git tag `prereg-v1.4.0-ge` and evaluated against the published **AiiDA Common Workflows (ACWF) FLEUR/WIEN2k all-electron reference equation of state** (Bosoni et al., *Nat. Rev. Phys.* 6, 45-58, 2024; Materials Cloud archive `yf0rj-w3r97`, SHA-256 `d7844caa127eae860fe5087ead42f80d1b6b5eb952a686ff4b912ddaed7db48b`).

### Key Scientific Findings:
1. **Definite Negative Transferability Result Across Chemical Rows:**
   While cross-engine parameter transplantation (importing cutoffs and local channels from ONCVPSP) successfully rescued silicon ($3s^2 3p^2$, row 3) in Phase 2, **it completely fails when applied to germanium ($[Ar] 3d^10 4s^2 4p^2$, row 4)**.
2. **Physical Mechanism of the Failure:**
   The presence of the filled $3d^10$ semicore shell severely constrains the norm-conservation condition in APE's Troullier–Martins solver. Transplanting tight multi-projector cutoffs ($r_c = 2.0$ bohr) causes APE's radial eigensolver to fail to bracket bound states during pseudopotential unscreening (`Unable to bracket eigenvalues for state: 1s`).
3. **Ghost State Dilemma in APE Single-Engine Tuning:**
   - In **Arm A (Baseline)**, omitting `LLocal` produces an ill-defined Kleinman–Bylander projector leading to complete lattice instability (monotonically declining energy with expanding volume; worst EOS error $\sim 2,810$ meV/atom).
   - In **Arm B (Single-Engine Repair)**, forcing `LLocal = 0` eliminates the $s$-channel bound ghost, but induces a severe negative ghost state in the $p$-channel ($E_{ref} > E_0, KB < 0$), causing total energies to diverge pathologically ($+92,079$ Ry) and destabilizing consumer SCF.
   - In **Arm C (Cross-Engine Repair)**, nominal transplanted cutoffs fail generation entirely. Expanding cutoffs to $+20\%$ ($r_c = 2.4, 2.64, 2.4$ bohr) allows UPF generation and clears APE atomic ghost checks, but yields unphysical overbinding in the crystal lattice ($+208,802$ Ry).
4. **Rigorous Evidence Ladder Stance:**
   In accordance with the binding L1–L6 evidence framework, **L6 (independent transferability across chemical families) remains strictly EMPTY**. We report this null/negative transferability result honestly and without qualification.

---

## 2. Experimental Setup & Preregistration

- **Element**: Germanium (Ge, $Z=32$)
- **Crystal Prototype**: Diamond cubic ($Fd\bar3m$, 2-atom primitive cell, space group 227)
- **Exchange-Correlation Functional**: PBE (Perdew-Burke-Ernzerhof, scalar-relativistic)
- **Reference Standard**: ACWF all-electron average (FLEUR & WIEN2k)
  - $V_0 = 47.8266\text{ \AA}^3$ (cell volume for 2 atoms)
  - $B_0 = 0.36774\text{ eV/\AA}^3 = 58.918\text{ GPa}$
  - $B'_0 = 4.8620$
  - Distortions evaluated: $[-4\%, -2\%, 0\%, +2\%, +4\%]$
- **Tolerances**:
  - Target error threshold (L5): $\le 2.0\text{ meV/atom}$
  - Numerical drift allowance: $\le 0.5\text{ meV/atom}$ ($\le 1/4$ error tolerance)
- **Budget Semantics**:
  > *`training_core_hours` is single-logical-CPU active training wall time enforced by CPU affinity. It is not a scheduler reservation; cluster-accounting adapters are future work.*

---

## 3. Results Summary Table

| Arm | Description | Parameters ($r_c^s, r_c^p, r_c^d$, $L_{loc}$) | L1 Gen | L2 Ser | L3 SCF | L4 Atomic Diag | L5 Accuracy (vs AE) | Feasible? | Budget (Core-h) |
| :--- | :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **Arm A** | Baseline (Unrepaired) | $2.66, 2.54, 2.65$ bohr; Default | PASS | PASS | PASS* | FAIL (ill-defined) | FAIL (2809.9 meV/atom) | **NO** | 0.000080 |
| **Arm B** | Single-Engine Repair | $2.66, 2.54, 2.65$ bohr; $L_{loc}=0$ | PASS | PASS | FAIL** | FAIL (p-ghost found) | FAIL (>90,000 Ry) | **NO** | 0.000045 |
| **Arm C-1** | Cross-Engine Nominal | $2.00, 2.20, 2.00$ bohr; $L_{loc}=0$ | FAIL | N/A | N/A | N/A (unscreening crash) | N/A | **NO** | 0.000000 |
| **Arm C-2** | Cross-Engine $+10\%$ | $2.20, 2.42, 2.20$ bohr; $L_{loc}=0$ | FAIL | N/A | N/A | N/A (unscreening crash) | N/A | **NO** | 0.000000 |
| **Arm C-3** | Cross-Engine $+20\%$ | $2.40, 2.64, 2.40$ bohr; $L_{loc}=0$ | PASS | PASS | FAIL** | PASS (no ghost) | FAIL (>200,000 Ry) | **NO** | 0.000035 |

\* *Converged only under Conjugate Gradient (`diagonalization = 'cg'`); Davidson failed due to unphysical projector.*
\*\* *Consumer SCF total energies exhibited unphysical non-variational divergence due to bound ghost state and unphysical core pseudization.*

---

## 4. Pareto Frontier (Cutoff vs Accuracy)

In an ideal pseudopotential design run, the Pareto frontier reflects a trade-off between plane-wave cutoff (computational cost) and holdout error against the all-electron reference:

```
Holdout Error (meV/atom)
    ^
    |
3000|  [Arm A @ 40 Ry: 2809.9 meV/atom]
    |           |        [Arm A @ 60 Ry: 2809.8 meV/atom]
    |
2000|
    |
1000|
    |
   2| -------------------------------------- Feasible Threshold (2.0 meV/atom)
    |
   0+----------------------------------------------------> Plane-wave cutoff (Ry)
           40 Ry                      60 Ry
```

Neither Arm B nor Arm C reached the feasible region (threshold $\le 2.0$ meV/atom). Consequently:
- **Feasible candidates discovered**: 0
- **Time/budget to first feasible candidate**: $\infty$ (budget exhausted without reaching feasibility)

---

## 5. Scientific Interpretation & Lessons for PseudoForge v1.4.0

1. **Why Cross-Engine Repair Worked for Si but Failed for Ge:**
   Silicon has a neon core ($1s^2 2s^2 2p^6$) and valence $3s^2 3p^2$. The absence of occupied $d$-states means the core and valence channels are well separated in radial extent, and Kleinman–Bylander localization with $L_{loc}=0$ produces smooth projectors that match both ONCVPSP and APE physics.
   In Germanium, the $3d^10$ subshell sits energetically near the valence region but is spatially compact. ONCVPSP handles this via an optimized polynomial local potential and multiple Vanderbilt projectors per channel. APE's single-projector Troullier-Martins formulation cannot support these tight radii without driving the unscreening ODE unstable.
2. **Impact on the v1.4.0 Manuscript & Claims:**
   - PseudoForge must **not** claim automated universal cross-engine repair.
   - The paper must frame cross-engine repair as an **interactive and diagnostic capability** that diagnoses defects across engines, provides initial donor parameters when transferable, and identifies fundamental physical limitations across chemical periods.
   - This negative result demonstrates the critical importance of preregistered holdouts: tuning methods exclusively on Si diamond created an illusion of universal transferability that broke down on Ge.
