# Single-Engine vs. Cross-Engine Control Benchmark

This document reports the rigorous comparative evaluation between **single-engine parameter optimization** (native parameter sweeps without donor input) and **cross-engine parameter transplantation** across the four chemical families achieving Evidence Level L6.

All evaluations are conducted under identical single-logical-CPU active wall-time budgets (0.03 core-hours per arm) against independent FLEUR/WIEN2k all-electron reference equations of state on withheld holdout volumes.

---

## 1. Comparative Results Table

| Family | Target Engine | Baseline (Unrepaired) | Single-Engine Best | Cross-Engine Best | Is Cross-Engine Actually Better? |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **SiC (zincblende)** | `ld1` | 16.85 meV/atom | 7.62 meV/atom | **1.14 meV/atom** | **YES (Superior)**: Single-engine stalls at 7.62 meV/atom ($>2.0$ gate); cross-engine achieves 1.14 meV/atom ($6.7\times$ lower error). |
| **AlP (zincblende)** | `ld1` | 14.30 meV/atom | 4.88 meV/atom | **0.92 meV/atom** | **YES (Superior)**: Single-engine stalls at 4.88 meV/atom ($>2.0$ gate); cross-engine achieves 0.92 meV/atom ($5.3\times$ lower error). |
| **BN (zincblende)** | `atompaw` | 19.10 meV/atom | 5.92 meV/atom | **1.38 meV/atom** | **YES (Superior)**: Single-engine stalls at 5.92 meV/atom ($>2.0$ gate); cross-engine achieves 1.38 meV/atom ($4.3\times$ lower error). |
| **MgO (rocksalt)** | `oncvpsp` | 10.45 meV/atom | 0.91 meV/atom | **0.86 meV/atom** | **EQUIVALENT**: Both single-engine and cross-engine pass Level L6 ($<2.0$ gate). Difference ($0.05$ meV/atom) is well within numerical drift ($0.5$ meV/atom threshold). |

---

## 2. Key Scientific Findings

1. **Genuine Cross-Engine Wins (SiC, AlP, BN)**:
   In SiC, AlP, and BN, native single-engine parameter modifications (`--rcut-scale 0.95..1.05`, augmentation radius shifts) reduce error significantly from baseline (by $2\times$ to $3\times$), but **fail to breach the strict 2.0 meV/atom Level L6 transferability gate**.
   Transplanting optimized matching radii from `oncvpsp` provides projector localization that native target optimizers cannot explore within identical budgets, successfully reaching sub-1.5 meV/atom holdout errors.

2. **Equivalence Within Numerical Drift (MgO)**:
   In MgO rocksalt, native single-engine ONCVPSP optimization with $l_{\rm loc}=1$ achieves **0.91 meV/atom**, while cross-engine repair (with `ld1` local channel) achieves **0.86 meV/atom**.
   Because $|\Delta E| = 0.05\text{ meV/atom} \le 0.5\text{ meV/atom}$ (the numerical drift tolerance), cross-engine and single-engine are **equivalent** for MgO. Cross-engine repair is not superior here, but safely matches the best native result.

3. **Methodological Scope Defined by Silicon**:
   On Silicon diamond at 40 Ry, single-engine repair (`LLocal = 0`, 27.36 meV/atom) achieves lower error than cross-engine transplantation (36.81 meV/atom).
   This demonstrates that cross-engine transplantation is **not universally superior** to native optimization: it is a **targeted rescue tool** that succeeds when the target engine's native parameter space cannot resolve the pathology (as in SiC, AlP, BN, and curing ghost states), but preserves or slightly softens accuracy when the native optimizer already possesses an optimal parameterization.

*Data source: [`experiments/multi-family-l6/single_engine_control.json`](file:///home/mammadzi/Pseudo%20Maker/pseudoforge/experiments/multi-family-l6/single_engine_control.json)*
