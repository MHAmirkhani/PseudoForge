# PseudoForge v1.4.0 Manuscript & Submission Status

> [!IMPORTANT]
> **DO NOT SUBMIT WITHOUT EXPLICIT AUTHOR APPROVAL.**
> Journal submission (Computer Physics Communications) is strictly an author action. No external publish, push, or submission operations may be performed automatically.

---

## 1. Manuscript Overview & Scientific Pivot

- **Title**: *PseudoForge v1.4.0: Cross-engine repair, parameter optimization, and empirical verification of electronic-structure pseudopotentials*
- **Target Journal**: *Computer Physics Communications* (Elsevier `elsarticle` class, `3p,twocolumn` layout)
- **Authors**: Mohammad Hossein Amirkhani (Corresponding author, `mohammadhossienamirkhani@gmail.com`) and Amirhossein Ahmadkhan Kordbacheh
- **Affiliation**: Iran University of Science and Technology, Tehran, Iran
- **Core Scientific Pivot**: Transition from generic multi-engine generation (v1.3.6) to automated cross-engine defect taxonomy, single-engine native parameter repairs, and cross-engine parameter transplantation (`--donor-engine`), bounded by an empirical six-level evidence hierarchy (L1--L6).

---

## 2. Compilation Instructions & Status

### Prerequisites
- TeX Live (2023 or newer) or MiKTeX with:
  - Document class: `elsarticle.cls`
  - Fonts: `lmodern`, `microtype`, `fontenc` (T1)
  - Packages: `amsmath`, `booktabs`, `tabularx`, `graphicx`, `hyperref`
- Python 3.10+ with `matplotlib` (for vector figure generation)

### Figure Regeneration
Vector PDF figures (`figures/architecture.pdf`, `figures/workflow.pdf`, `figures/si_repair.pdf`, and `figures/ge_comparison.pdf`) are generated directly from version-controlled numerical outputs (`examples/design-repair/results/results.json` and `experiments/ge-repair-comparison/results.json`):
```bash
python3 make_figures.py
```
*(Or with the local virtual environment: `../server/.venv/bin/python3 make_figures.py`)*

### PDF Compilation
From the `manuscript-v1.4.0/` directory:
```bash
pdflatex -halt-on-error -interaction=nonstopmode main.tex
bibtex main
pdflatex -halt-on-error -interaction=nonstopmode main.tex
pdflatex -halt-on-error -interaction=nonstopmode main.tex
```

---

## 3. Claim-to-Evidence Mapping (L1–L6 Ladder)

Every claim in `main.tex` is strictly pinned to version-controlled artifacts and measured evidence levels:

| Manuscript Claim / Section | Evidence Level | Supporting File / Repository Artifact | Empirical Outcome |
| :--- | :--- | :--- | :--- |
| **9-Engine Native Generation** (Sec. 2.1) | **L1** | `tools/audit.sh`, `AUDIT.md`, `tests/test_engine_matrix.sh` | 9/9 engines exit 0 and emit primary files |
| **Multi-Format Serialization** (Sec. 2.1) | **L2** | `tests/test_validate.sh`, `data/formats.tsv` | Strict validation of UPF v2, PSP8, PAW-XML, CPI, GTH |
| **Consumer SCF Convergence** (Sec. 2.1) | **L3** | `tests/test_engine_matrix.sh`, `tests/test_http.sh` | Plane-wave SCF convergence in QE \texttt{pw.x}, ABINIT, CP2K |
| **Defect Detection & Elimination** (Sec. 2.2) | **L4** | `data/defects/taxonomy.tsv`, `tests/test_repair.sh` | Elimination of bound ghosts via \texttt{LLocal = 0} in APE Si |
| **Silicon Diamond Material Accuracy** (Sec. 3.1) | **L5** | `examples/design-repair/results/results.json` | APE Si worst EOS error reduced from 74.05 to 1.26 meV/atom via ONCVPSP donor transplantation |
| **Preregistered Germanium Experiment** (Sec. 3.2) | **L5** | `experiments/ge-repair-comparison/results.json`, Git tag `prereg-v1.4.0-ge` | ACWF FLEUR/WIEN2k reference benchmark; negative transferability finding across chemical rows |
| **Out-of-Family Transferability** (Sec. 3.2, 4) | **L6** | `docs/contributing/evidence-status.md`, `experiments/ge-repair-comparison/analysis.md` | **EMPTY**: Ge diamond transferability fails ($\Delta E > 2.0$ meV/atom); no engine achieves L6 |
| **Single-CPU Computational Budget** (Sec. 2.4, 4) | N/A | `tools/pf_design.py`, `docs/contributing/evidence-status.md` | \texttt{training\_core\_hours} enforced via single-logical-CPU affinity pinning |
| **Negative Results Register** (Sec. 3.3) | N/A | `docs/contributing/evidence-status.md`, `PSEUDOFORGE_HANDOFF.md` | Permanent archive of silanone, GTH $k$-mesh, Ti/O null, OPIUM semicore, and AtomPAW Ti failures |

---

## 4. Pre-Submission Author Review Checklist

Before approving or executing any submission to *Computer Physics Communications*, the authors must verify:

- [ ] **Author Names and Affiliations**: Review author list, institutional affiliations, and corresponding email address (`mohammadhossienamirkhani@gmail.com`).
- [ ] **Empirical Reach and Non-Exceedance**: Ensure that no sentence in prose claims or implies Evidence Level L6 out-of-family transferability.
- [ ] **Preregistration Record**: Confirm Git tag `prereg-v1.4.0-ge` at commit `fd5a059` correctly references the unchanged ACWF FLEUR/WIEN2k dataset hash (`d7844caa...`).
- [ ] **Budget Semantics**: Confirm that all mentions of compute budgets explicitly identify `training_core_hours` as single-CPU wall-time with core affinity, not scheduler reservations.
- [ ] **Holdout Integrity**: Confirm that Si diamond, TiO, TiO$_2$, silane, and silanone remain designated as calibration-only.
- [ ] **PDF Typography**: Verify that the compiled `main.pdf` has zero undefined citations (`?`), zero broken cross-references (`??`), and clean twocolumn table formatting.
- [ ] **Final Submission Execution**: **Must be performed manually by the author.** (No automated bots or AI agents may submit to Elsevier).
