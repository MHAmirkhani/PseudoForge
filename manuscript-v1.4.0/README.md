# PseudoForge v1.4.0 Manuscript & Submission Status

> [!IMPORTANT]
> **DO NOT SUBMIT WITHOUT EXPLICIT AUTHOR APPROVAL.**
> Journal submission (*Computer Physics Communications*) is strictly an author action. No external publish, push, or submission operations may be performed automatically.

---

## 1. Manuscript Overview & Scientific Pivot

- **Title**: *PseudoForge v1.4.0: Cross-engine repair, parameter optimization, and empirical verification of electronic-structure pseudopotentials*
- **Target Journal**: *Computer Physics Communications* (Elsevier `elsarticle` class, `3p,twocolumn` layout)
- **Authors**: Mohammad Hossein Amirkhani (Corresponding author, `mohammadhossienamirkhani@gmail.com`) and Amirhossein Ahmadkhan Kordbacheh
- **Affiliation**: Iran University of Science and Technology, Tehran, Iran
- **Core Scientific Pivot**: Transition from generic multi-engine generation (v1.3.6) to automated cross-engine defect taxonomy, single-engine native parameter repairs, and cross-engine parameter transplantation (`--donor-engine`), bounded by an empirical six-level evidence hierarchy (L1--L6).
- **Evidence Level L6 Populated**: Out-of-family transferability (L6) is systematically populated across four fresh chemical families (SiC, AlP, BN, and MgO) with holdout errors below 1.5 meV/atom, while establishing a precise physical applicability boundary on transition-adjacent systems (GaAs, Ge) governed by filled $3d^{10}$ semicore unscreening.

---

## 2. Compilation Instructions & Provenance

### Provenance of `main.pdf`
The build environment in the local Linux/WSL instance does not have a native `pdflatex` binary in its Linux `$PATH`. The checked-in PDF artifact was compiled using the host MiKTeX distribution (`pdflatex.exe` 24.1+) on Windows:
```cmd
cd "C:\Users\mamma\...\Pseudo Maker\pseudoforge\manuscript-v1.4.0"
pdflatex -halt-on-error -interaction=nonstopmode main.tex
bibtex main
pdflatex -halt-on-error -interaction=nonstopmode main.tex
pdflatex -halt-on-error -interaction=nonstopmode main.tex
```
On standard Linux installations with TeX Live:
```bash
sudo apt-get install texlive-latex-extra texlive-fonts-recommended
pdflatex -halt-on-error -interaction=nonstopmode main.tex
bibtex main
pdflatex -halt-on-error -interaction=nonstopmode main.tex
pdflatex -halt-on-error -interaction=nonstopmode main.tex
```

### Figure Regeneration
Vector PDF figures (`architecture.pdf`, `workflow.pdf`, `si_repair.pdf`, `ge_comparison.pdf`, and `domain_map.pdf`) are generated directly from version-controlled numerical outputs (`examples/design-repair/results/results.json`, `experiments/ge-repair-comparison/results.json`, and `experiments/multi-family-l6/results.json`):
```bash
../server/.venv/bin/python3 make_figures.py
```

---

## 3. Claim-to-Evidence Mapping (L1–L6 Ladder)

Every claim in `main.tex` is strictly pinned to version-controlled artifacts and measured evidence levels:

| Manuscript Claim / Section | Evidence Level | Supporting File / Repository Artifact | Empirical Outcome |
| :--- | :--- | :--- | :--- |
| **9-Engine Native Generation** (Sec. 2.1) | **L1** | `tools/audit.sh`, `AUDIT.md`, `tests/test_engine_matrix.sh` | 9/9 engines exit 0 and emit primary files |
| **Multi-Format Serialization** (Sec. 2.1) | **L2** | `tests/test_validate.sh`, `data/formats.tsv` | Strict validation of UPF v2, PSP8, PAW-XML, CPI, GTH |
| **Consumer SCF Convergence** (Sec. 2.1) | **L3** | `tests/test_engine_matrix.sh`, `tests/test_http.sh` | Plane-wave SCF convergence in QE `pw.x`, ABINIT, CP2K |
| **Defect Detection & Elimination** (Sec. 2.2) | **L4** | `data/defects/taxonomy.tsv`, `tests/test_repair.sh` | Elimination of bound ghosts via `LLocal = 0` in APE Si |
| **Silicon Diamond Material Accuracy** (Sec. 3.1) | **L5** | `examples/design-repair/results/results.json` | APE Si ghost cured via ONCVPSP donor (36.81 meV/atom at 40 Ry); native ONCVPSP achieves 1.26 meV/atom |
| **Single-Engine Optimization Controls** (Sec. 3.2) | **L6** | `experiments/multi-family-l6/single_engine_control.json`, `docs/contributing/single-engine-control.md` | Genuine win in SiC (6.7×), AlP (5.3×), BN (4.3×); MgO equivalent within drift (0.05 meV/at) |
| **Out-of-Family Transferability** (Sec. 3.2) | **L6** | `experiments/multi-family-l6/results.json`, Git tag `prereg-v1.4.0-l6-multifamily` | **POPULATED**: SiC (1.14 meV), AlP (0.92 meV), BN (1.38 meV), MgO (0.86 meV) pass L6 |
| **Applicability Boundary & Partial Rescue** (Sec. 3.2, 4) | N/A | `docs/contributing/domain-of-applicability.md`, `data/defects/unified_controls.tsv` | Ge partial rescue (2809 to 11.83 meV/atom, 237x); GaAs (18.94 meV) and Ge define boundary governed by filled $3d^{10}$ semicore unscreening |
| **Single-CPU Computational Budget** (Sec. 2.3, 4) | N/A | `tools/pf_design.py`, `docs/contributing/evidence-status.md` | `training_core_hours` enforced via single-logical-CPU affinity pinning |

---

## 4. Submission Checklist & Author Decision Escalations

The following decisions require explicit author resolution prior to journal submission:

1. **DOI Allocation**:
   - The current DOI in `main.tex` and `Program summary` references v1.3.6 (`10.5281/zenodo.24017550`).
   - *Option A (Recommended)*: Reserve a new version DOI on Zenodo for v1.4.0 upon publication.
   - *Option B*: Reference the precise commit hash (`8758729` or final release commit).
   - *Option C*: Reference the direct GitHub release URL (`https://github.com/MHAmirkhani/PseudoForge/releases/tag/v1.4.0`).
2. **Release Tag `v1.4.0`**:
   - Tagging `v1.4.0` is permanently deferred to the author. Internal preregistration tags (`prereg-v1.4.0-ge`, `prereg-v1.4.0-l6-multifamily`) are set locally.
3. **Corresponding Author Verification**:
   - Corresponding author email verified as `mohammadhossienamirkhani@gmail.com`.
4. **Final Submission Execution**:
   - **Must be performed manually by the author.** No automated agent will attempt external interactions.
