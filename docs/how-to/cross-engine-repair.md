# How to Repair Pseudopotential Defects

PseudoForge includes an automated defect diagnosis and repair subsystem (`pseudoforge repair`) backed by an evidence-grounded defect taxonomy (`data/defects/taxonomy.tsv`). When a generated pseudopotential suffers from unphysical ghost states, high-energy transferability drift, numerical instabilities, or serialization errors, you can repair it either by adjusting native engine parameters or by importing proven physical control parameters from another engine.

---

## 1. When to Use Single-Engine vs. Cross-Engine Repair

### Single-Engine Repair (`--strategy single_engine_repair`)
Use single-engine repair when the generator's underlying formulation is capable of producing an accurate potential, but the chosen native controls (e.g. default projector channel, matching radius, or grid boundaries) triggered a known defect:
- **APE local-channel defect**: APE defaults to the highest angular momentum channel when unspecified, producing an unphysical bound ghost state in the $s$-channel for silicon. Setting `LLocal = 0` (local channel $s$) resolves the ghost state directly within APE.
- **USPP delimiter fault**: Concatenation of floating-point values in the `<PP_QFCOEF>` block during UPF serialization. Re-delimiting the block with whitespace restores schema compliance without re-running the generator.
- **fhi98PP PSP6 metadata missing**: CPI pseudopotentials missing required ABINIT format-6 header cards. Prepending explicit metadata cards resolves consumer parsing failures.
- **ADPACK grid bounds**: Array overflow in `readfile.c` when radial grid point counts exceed 20,000 points. Clamping `grid.num` to safe ranges resolves memory corruption.

### Cross-Engine Repair (`--strategy cross_engine_repair`)
Use cross-engine repair when native heuristics within an engine fail to produce a transferable potential, but a mature parameterization exists in another engine (the donor):
- **APE Si ghost state**: Repaired by importing ONCVPSP's proven local channel choice ($l=0$) and cutoff radii ($r_c(s) = 1.60$, $r_c(p) = 1.71$ bohr).
- **OPIUM Si high-energy transferability drift**: Repaired by importing `ld1.x` matching radii ($r_c = 1.80$ bohr), reducing worst transferability error below the 2.0 meV/atom tolerance.
- **AtomPAW Ti semicore failure**: Repaired by importing ONCVPSP's semicore configuration ($3s^2 3p^6 3d^2 4s^2$, $Z_{\text{val}} = 12$) and projector radii, passing the metallic training gate.
- **GTH CP2K $k$-mesh instability**: Repaired by importing real-space projector configurations from ONCVPSP, eliminating ranking inversion under $k$-mesh tightening.

---

## 2. Parameter Mapping Table Between Engines

The table below outlines compatible donor-target pairs in PseudoForge's cross-engine repair system:

| Target Engine | Target Defect | Donor Engine | Imported Parameters | Physical Target |
| :--- | :--- | :--- | :--- | :--- |
| **APE** | Bound ghost state in $s$-channel | **ONCVPSP** | `lloc = 0`, $r_c(s) = 1.60$, $r_c(p) = 1.71$ bohr | Shift local channel and match real-space projector cutoffs |
| **OPIUM** | Material transferability $> 2$ meV/atom | **ld1.x** | Matching radii $r_c = 1.80$ bohr | Tighten augmentation/cutoff radii to suppress high-energy drift |
| **AtomPAW** | Metallic training gate rejection | **ONCVPSP** | Semicore valence partition ($Z_{\text{val}}=12$, $3s3p3d4s$) | Eliminate unphysical core overlap in dense environments |
| **GTH** | $k$-mesh ranking inversion in CP2K | **ONCVPSP** | Real-space projector radii and cutoff scales | Prevent real-space aliasing across fine grids |

---

## 3. Step-by-Step Tutorial: Repairing APE Silicon

### Step 1: Diagnose Existing Project Defects
Run `pseudoforge repair` in dry-run mode to inspect a project directory without modifying any files:
```bash
pseudoforge repair ./my-silicon-project --dry-run
```
Output:
```text
INFO  repair: detected 1 defect(s) in ./my-silicon-project:
  - [ape-si-ghost] engine: ape | class: atomic_ghost_state
    detector: detect_bound_ghost (summary.txt/diagnostic_log)
    available strategy: single_engine_repair (lloc=s)
    evidence: v14-nine-engine-optimization/qe-silicon-results.csv
    cross-engine source: oncvpsp
INFO  dry-run: no files modified
```

### Step 2: Apply Single-Engine Repair
To apply the native parameter adjustment:
```bash
pseudoforge repair ./my-silicon-project --strategy single_engine_repair
```
This leaves the original output untouched and writes the repaired deck and UPF into:
`./my-silicon-project/repair/ape-si-ghost/<timestamp>/`.

### Step 3: Apply Cross-Engine Repair
To import proven parameters from an ONCVPSP donor:
```bash
pseudoforge repair ./my-silicon-project --strategy cross_engine_repair --donor-engine oncvpsp
```
The subsystem:
1. Locates the donor parameters from the PseudoDojo / SG15 registry (`ONCVPSP-PBE-PDv0.4/Si/Si.in`).
2. Translates the local channel ($l=0$) and radii ($r_c = 1.60, 1.71$ bohr) into APE's `%PPComponents` syntax.
3. Invokes APE to regenerate the pseudopotential into `./my-silicon-project/repair/ape-si-ghost/cross-oncvpsp-<timestamp>/`.
4. Runs L1–L4 checks, verifying that the bound ghost state is eliminated.
5. Updates `./my-silicon-project/reports/repairs.json`.

---

## 4. Caveats and Limitations

> [!CAUTION]
> **Cross-Engine Translation is an Approximation**:
> Each generator implements distinct mathematical formulations (e.g. Troullier–Martins pseudization vs Hamann generalized norm-conserving projectors vs Vanderbilt ultrasoft augmentations). Cutoff radii and projector boundaries imported from a donor engine provide excellent initial guesses and resolve topological faults (such as ghost states), but they do not guarantee mathematical equivalence. Always validate repaired pseudopotentials through L4 atomic diagnostics and L5 all-electron benchmarks.

### Evidence Levels (L1–L6)
PseudoForge operates on a strict evidence hierarchy:
- **L1**: Native generation success and execution timing.
- **L2**: Valid serialization and UPF schema integrity.
- **L3**: Consumer SCF convergence in Quantum ESPRESSO.
- **L4**: Atomic diagnostics (absence of ghost states, logarithmic derivative continuity).
- **L5**: Material accuracy against independent all-electron reference (e.g. ACWF FLEUR/WIEN2k EOS).
- **L6**: Independent transferability on a fresh chemical family sharing zero geometries or environments with training sets.

### Holdout Ledger Lockbox
Holdouts consumed in prior work (Si diamond, TiO, TiO₂, silane, and silanone) are permanently locked as calibration sets. Any fresh transferability assessment (L6) must use completely fresh chemical systems (e.g. Germanium diamond or SiC).

### Training Budget Semantics
`training_core_hours` is single-logical-CPU active training wall time enforced by CPU affinity. It is not a scheduler reservation; cluster-accounting adapters are future work.
