#!/usr/bin/env python3
"""Physics-oriented regression tests; solver fixtures are never reference data."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("pf_design", ROOT / "tools/pf_design.py")
design = importlib.util.module_from_spec(spec)
spec.loader.exec_module(design)

TEMPLATE = """&CONTROL
 calculation='scf', pseudo_dir='{{PSEUDO_DIR}}', outdir='{{OUTDIR}}', prefix='{{PREFIX}}', tprnfor=.true., tstress=.true.
/
&SYSTEM
 ibrav=1, celldm(1)=10, nat=1, ntyp=1, ecutwfc={{ECUTWFC}}, ecutrho={{ECUTRHO}}
/
&ELECTRONS
 conv_thr=1d-10
/
ATOMIC_SPECIES
 Si 28.085 {{UPF}}
ATOMIC_POSITIONS crystal
 Si 0 0 0
K_POINTS gamma
! CASE
"""


class DesignTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="pf design tests ")
        self.root = Path(self.temp.name)
        self.addCleanup(self.temp.cleanup)
        for split in ("train", "test"):
            (self.root / (split + ".in")).write_text(TEMPLATE.replace("! CASE", "! " + split).replace("celldm(1)=10", "celldm(1)=" + ("10" if split == "train" else "11")))
        self.protocol = {
            "schema_version": 1, "element": "Si", "xc": "pbe", "relativity": "scalar", "repeats": 1,
            "candidates": [{"id": "si", "engine": "ld1", "family": "paw", "profile": "psl-high",
                            "options": {}, "ecutwfc": 30, "ecutrho": 240}],
            "benchmarks": [{"id": split, "split": split, "input": split + ".in",
                            "reference": {"source": "synthetic unit-test fixture, not physical reference data", "kind": "synthetic-test",
                                          "xc": "pbe", "relativity": "scalar", "forces_Ry_bohr": [[0, 0, 0]]},
                            "tolerances": {"force_max_Ry_bohr": 0.001}} for split in ("train", "test")],
        }

    def load(self, protocol=None):
        path = self.root / "protocol.json"
        path.write_text(json.dumps(self.protocol if protocol is None else protocol))
        return design.load_protocol(path)

    def test_valid_protocol_with_spaces(self):
        protocol = self.load()
        self.assertEqual(protocol["benchmarks"][0]["composition"], ("Si",))

    def test_grid_expansion_preserves_physics(self):
        self.protocol["candidates"][0]["grid"] = {"rcut_scale": [0.9, 1.1], "nlcc": ["on", "off"]}
        protocol = self.load()
        self.assertEqual(len(protocol["candidates"]), 4)
        args = design.generation_args(protocol, protocol["candidates"][0], self.root / "candidate")
        self.assertIn("--no-autofix", args)
        self.assertIn("--rcut-scale", args)

    def test_seeded_plan_reports_and_limits_trials(self):
        self.protocol["candidates"][0]["grid"] = {"rcut_scale": [0.95, 1.0, 1.05]}
        self.protocol["search"] = {"strategy": "random", "seed": 19, "max_trials": 2}
        self.load()
        rc = self.root / "rc"
        rc.touch()
        env = dict(os.environ, PF_RC=str(rc), LD1_BIN=str(ROOT / "tests/mock/ld1.x"))
        orders = []
        for name in ("first", "second"):
            out = self.root / name
            command = [str(ROOT / "pseudoforge"), "design", str(self.root / "protocol.json"),
                       "--plan", "-o", str(out)]
            result = subprocess.run(command, env=env, text=True, capture_output=True, timeout=90)
            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            report = json.loads((out / "report.json").read_text())
            orders.append(report["search"]["trial_order"])
            self.assertEqual(report["search"]["candidate_count"], 3)
            self.assertEqual([item["id"] for item in report["previews"]], orders[-1])
        self.assertEqual(orders[0], orders[1])
        self.assertEqual(len(set(orders[0])), 2)
        self.protocol["search"]["max_trials"] = 4
        with self.assertRaisesRegex(ValueError, "max_trials"):
            self.load()

    def test_uniform_search_balances_available_engine_formulation_pairs(self):
        trials = [({"id": f"{engine}-{family}-{index}", "engine": engine, "family": family}, [])
                  for engine, family, size in (("ld1", "us", 1), ("ld1", "paw", 4), ("oncvpsp", "nc", 3))
                  for index in range(size)]
        spec = {"strategy": "uniform", "seed": 42, "max_trials": 6}
        ordered = design.order_trials(trials, spec)
        arms = [(candidate["engine"], candidate["family"]) for candidate, _ in ordered]
        self.assertEqual(len(set(arms[:3])), 3)
        self.assertEqual(len(set(arms[3:5])), 2)
        self.assertEqual(len({candidate["id"] for candidate, _ in ordered}), 6)
        self.assertEqual(ordered, design.order_trials(list(reversed(trials)), spec))

    def test_missing_reference_or_mismatched_theory_is_refused(self):
        for change in ({"source": ""}, {"xc": "pz"}, {"relativity": "full"}, {"forces_Ry_bohr": [[0, 0]]}):
            with self.subTest(change=change):
                protocol = copy.deepcopy(self.protocol)
                protocol["benchmarks"][0]["reference"].update(change)
                with self.assertRaises(ValueError):
                    self.load(protocol)

    def test_unknown_options_and_nonfinite_values_are_refused(self):
        for options in ({"unknown": 1}, {"rcut_scale": float("nan")}, {"lsd": "yes"}, {"extra_projectors": "3D:0.5"}):
            with self.subTest(options=options), self.assertRaises(ValueError):
                design.option_args(options)

    def test_training_test_duplication_and_missing_split_are_refused(self):
        (self.root / "test.in").write_text((self.root / "train.in").read_text())
        with self.assertRaisesRegex(ValueError, "both train and test"):
            self.load()
        self.protocol["benchmarks"][1]["split"] = "train"
        with self.assertRaisesRegex(ValueError, "both train and held-out"):
            self.load()

    def test_incompatible_energy_anchors_are_refused(self):
        self.protocol["benchmarks"][0]["tolerances"] = {"relative_energy_Ry_atom": 0.001}
        self.protocol["benchmarks"][0]["relative_to"] = "test"
        for case in self.protocol["benchmarks"]:
            case["reference"]["energy_Ry"] = -10
        with self.assertRaisesRegex(ValueError, "same composition and split"):
            self.load()

    def test_declared_group_cannot_leak_across_splits(self):
        self.protocol["benchmarks"][0]["group"] = "diamond"
        self.protocol["benchmarks"][1]["group"] = "diamond"
        with self.assertRaisesRegex(ValueError, "group diamond appears in both"):
            self.load()
        self.protocol["benchmarks"][1]["group"] = "fluorite"
        self.load()

    def test_energy_gauge_cancels_in_relative_energy(self):
        case = {"id": "b", "relative_to": "a", "composition": ["Si", "Si"], "tolerances": {"relative_energy_Ry_atom": 0.01}, "reference": {"energy_Ry": -8}}
        anchor = {"reference": {"energy_Ry": -10}}
        actual = {"a": {"energy_Ry": -100}, "b": {"energy_Ry": -98.002}}
        error = design.measure_errors(case, actual["b"], actual, {"a": anchor})
        self.assertAlmostEqual(error["relative_energy_Ry_atom"], 0.001)

    def test_qe_parser_requires_convergence_and_correct_units(self):
        text = """!    total energy = -1.25D+01 Ry
atom 1 type 1 force = 1.0D-03 0.0 -2.0D-03
total   stress (Ry/bohr**3) (kbar) P= 0.0
 0.1 0.2 0.3 1.0 2.0 3.0
 0.4 0.5 0.6 4.0 5.0 6.0
 0.7 0.8 0.9 7.0 8.0 9.0
JOB DONE.
"""
        value = design.parse_qe(text, 1)
        self.assertEqual(value["energy_Ry"], -12.5)
        self.assertEqual(value["stress_kbar"][0], [1, 2, 3])
        self.assertEqual(value["forces_Ry_bohr"][0], [0.001, 0, -0.002])
        for invalid in (text.replace("JOB DONE.", ""), text + "convergence NOT achieved", text.replace("-1.25D+01", "NaN")):
            with self.assertRaises(ValueError):
                design.parse_qe(invalid, 1)

    def test_convergence_levels_must_tighten_and_require_mesh_token(self):
        self.protocol["convergence"] = {
            "base_k_mesh": [4, 4, 4], "tolerance_fraction": 0.1,
            "levels": [{"ecutwfc": 40, "ecutrho": 240, "k_mesh": [4, 4, 4]}],
        }
        with self.assertRaisesRegex(ValueError, "K_POINTS automatic"):
            self.load()
        for path in self.root.glob("*.in"):
            path.write_text(path.read_text().replace("K_POINTS gamma", "K_POINTS automatic\n{{K_MESH}} 0 0 0"))
        self.load()
        for change in ({"k_mesh": [4, 3, 4]}, {"ecutwfc": 30}, {"ecutrho": 200}):
            with self.subTest(change=change), self.assertRaises(ValueError):
                protocol = copy.deepcopy(self.protocol)
                protocol["convergence"]["levels"][0].update(change)
                self.load(protocol)

    def test_numerical_drift_uses_signed_difference_not_absolute_error_delta(self):
        anchor = {"id": "a", "composition": ["Si"], "tolerances": {}}
        case = {"id": "b", "relative_to": "a", "composition": ["Si"],
                "tolerances": {"relative_energy_Ry_atom": 0.01}}
        earlier = {"cases": [{"id": "a", "measurements": [{"energy_Ry": -100.0}]},
                             {"id": "b", "measurements": [{"energy_Ry": -99.998}]}]}
        later = {"cases": [{"id": "a", "measurements": [{"energy_Ry": -101.0}]},
                           {"id": "b", "measurements": [{"energy_Ry": -101.002}]}]}
        drift = design.numerical_drift([anchor, case], earlier, later, 0.1)
        self.assertAlmostEqual(drift["changes"]["b"]["relative_energy_Ry_atom"], 0.004)
        self.assertFalse(drift["passes"])

    def test_end_to_end_rejects_numerical_drift_even_with_reference_passes(self):
        self.protocol["convergence"] = {
            "base_k_mesh": [4, 4, 4], "tolerance_fraction": 0.1,
            "levels": [{"ecutwfc": 40, "ecutrho": 240, "k_mesh": [6, 6, 6]}],
        }
        for path in self.root.glob("*.in"):
            path.write_text(path.read_text().replace("K_POINTS gamma", "K_POINTS automatic\n{{K_MESH}} 0 0 0"))
        self.load()
        solver = self.root / "pw-fixture"
        solver.write_text("#!/usr/bin/env python3\nimport sys\ns = sys.stdin.read()\nf = 0.0005 if '6 6 6 0 0 0' in s else 0\nprint('! total energy = -10 Ry')\nprint(f'atom 1 type 1 force = {f} 0 0')\nprint('JOB DONE.')\n")
        solver.chmod(0o755)
        rc = self.root / "rc"
        rc.touch()
        output = self.root / "report"
        env = dict(os.environ, PF_RC=str(rc), LD1_BIN=str(ROOT / "tests/mock/ld1.x"),
                   MOCK_FAIL_ELEMENTS="", MOCK_FAIL_ALWAYS="")
        command = [str(ROOT / "pseudoforge"), "design", str(self.root / "protocol.json"),
                   "--pw", str(solver), "-o", str(output)]
        result = subprocess.run(command, env=env, text=True, capture_output=True, timeout=90)
        self.assertEqual(result.returncode, 2, result.stderr + result.stdout)
        report = json.loads((output / "report.json").read_text())
        assessment = report["results"][0]["training"]
        self.assertTrue(assessment["reference_passes"])
        self.assertTrue(assessment["convergence"]["levels"][0]["assessment"]["passes"])
        self.assertFalse(assessment["convergence"]["passes"])
        self.assertIsNone(report["selected"])

    def test_pareto_uses_feasible_training_results_only(self):
        results = [{"id": str(i), "training": {"passes": p, "cost_seconds": c, "worst_normalized_error": e}}
                   for i, (p, c, e) in enumerate([(True, 1, .5), (True, 2, .6), (True, 3, .2), (False, .1, 2)])]
        self.assertEqual(design.pareto(results), ["0", "2"])

    def test_end_to_end_keeps_held_out_failure_and_never_certifies_synthetic_data(self):
        self.load()
        # This is an execution fixture, explicitly labelled synthetic-test.
        # The real Bash generator is run with the existing mock atomic solver.
        pw = self.root / "pw-fixture"
        pw.write_text("#!/usr/bin/env python3\nimport sys\ns=sys.stdin.read()\nf=0.0 if '! train' in s else 0.01\nprint('! total energy = -10.0 Ry')\nprint(f'atom 1 type 1 force = {f} 0 0')\nprint('JOB DONE.')\n")
        pw.chmod(0o755)
        rc = self.root / "rc"
        rc.write_text("# isolated execution fixture\n")
        env = dict(os.environ, PF_RC=str(rc), LD1_BIN=str(ROOT / "tests/mock/ld1.x"), MOCK_FAIL_ELEMENTS="", MOCK_FAIL_ALWAYS="")
        output = self.root / "out"
        command = [str(ROOT / "pseudoforge"), "design", str(self.root / "protocol.json"), "--pw", str(pw), "-o", str(output)]
        result = subprocess.run(command, env=env, text=True, capture_output=True, timeout=90)
        self.assertEqual(result.returncode, 2, result.stderr + result.stdout)
        report = json.loads((output / "report.json").read_text())
        self.assertEqual(report["selected"], "si")
        self.assertTrue(report["results"][0]["training"]["passes"])
        self.assertFalse(report["test"]["passes"])
        self.assertFalse(report["meets_reference_constraints"])
        self.assertEqual(report["reference_kinds"], ["synthetic-test"])
        usage = report["resource_accounting"]
        self.assertGreater(usage["heldout_cpu_seconds"], 0)
        self.assertGreater(usage["generation_cpu_seconds"], 0)
        self.assertGreaterEqual(usage["training_trial_cpu_seconds"], usage["generation_cpu_seconds"])
        second = subprocess.run(command, env=env, text=True, capture_output=True, timeout=30)
        self.assertNotEqual(second.returncode, 0)
        self.assertIn("existing runs are never removed", second.stderr)


if __name__ == "__main__":
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(DesignTests)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    failed = len(result.failures) + len(result.errors)
    print(f"{result.testsRun - failed - len(result.skipped)} passed, {failed} failed, {len(result.skipped)} skipped")
    raise SystemExit(not result.wasSuccessful())
