
# Three-Way Comparative Repair Demonstration: Silicon Diamond

| Arm | Strategy / Donor | L1 (Gen) | L2 (UPF) | L3 (SCF) | L4 (Ghost) | L5 (EOS Error) | Verdict |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Baseline (Unrepaired APE)** | `None` (rc=2.38/3.56) | PASS (1.724s) | PASS | PASS | FAIL (ghost in s) | 74.05 meV/atom | **DEFECTIVE** |
| **Single-Engine Repair** | `0` (rc=2.38/3.56) | PASS (1.571s) | PASS | PASS | PASS (0 ghosts) | 27.36 meV/atom | REPAIRED |
| **Cross-Engine Repair (ONCVPSP Donor)** | `0` (rc=1.6/1.71) | PASS (1.572s) | PASS | PASS | PASS (0 ghosts) | 36.81 meV/atom | REPAIRED |
