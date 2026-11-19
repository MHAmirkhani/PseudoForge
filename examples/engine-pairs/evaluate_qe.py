#!/usr/bin/env python3
"""Evaluate native pairs that export scalar-PBE silicon UPFs against Si EOS."""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import json
import os
from pathlib import Path
import shutil
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
import pf_design as design


def assess(arm, native, output, protocol, pw, env):
    folder = output / arm["engine"]
    folder.mkdir()
    train = [case for case in protocol["benchmarks"] if case["split"] == "train"]
    test = [case for case in protocol["benchmarks"] if case["split"] == "test"]
    reference_settings = protocol["candidates"][0]
    results = []
    for entry in arm["trials"]:
        trial = {"id": entry["id"], "training": None}
        if "output" not in entry:
            trial["error"] = entry.get("native_summary", {}).get("message") or "native generation gave no deliverable"
        else:
            candidate = folder / entry["id"]
            pseudos = candidate / "pseudos"
            pseudos.mkdir(parents=True)
            source = native / entry["output"]
            target = pseudos / source.name
            shutil.copyfile(source, target)
            if design.digest(target) != entry["sha256"]:
                raise ValueError(f"{source}: native artifact digest changed")
            trial["pseudo_sha256"] = entry["sha256"]
            try:
                trial["training"] = design.evaluate(protocol, reference_settings, candidate, train, pw, env)
            except (ValueError, OSError) as error:
                trial["error"] = str(error)
        results.append(trial)
        design.write_json(folder / "report.json", {"engine": arm["engine"], "family": arm["family"],
                                                   "trials": results, "stage": "training"})
    baseline = results[0]
    alternatives = [trial for trial in results[1:] if (trial["training"] or {}).get("passes")]
    winner = min(alternatives, key=lambda trial: (trial["training"]["worst_normalized_error"], trial["id"]),
                 default=None)
    report = {"engine": arm["engine"], "family": arm["family"], "trials": results,
              "selected_tuned_on_training_only": winner["id"] if winner else None}
    design.write_json(folder / "report.json", report)
    for trial in (baseline, winner):
        if trial and (trial["training"] or {}).get("passes"):
            try:
                trial["test"] = design.evaluate(protocol, reference_settings, folder / trial["id"], test, pw, env)
            except (ValueError, OSError) as error:
                trial["test"] = {"passes": False, "error": str(error)}
    design.write_json(folder / "report.json", report)
    print(arm["engine"], report["selected_tuned_on_training_only"], flush=True)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("native_report", type=Path)
    parser.add_argument("si_protocol", type=Path, help="matched Si PBE EOS example protocol")
    parser.add_argument("--pw", required=True)
    parser.add_argument("--jobs", type=int, default=3)
    parser.add_argument("-o", "--output", type=Path, required=True)
    args = parser.parse_args()
    solver = shutil.which(args.pw)
    if not solver or args.jobs < 1:
        parser.error("provide an installed pw.x and a positive job count")
    protocol = design.load_protocol(args.si_protocol)
    if (protocol["element"], protocol["xc"], protocol["relativity"]) != ("Si", "pbe", "scalar"):
        parser.error("use the scalar-PBE silicon EOS pilot protocol")
    if protocol["fixed_pseudos"]:
        parser.error("this evaluator expects elemental Si without fixed species")
    args.output.mkdir()
    native = args.native_report.parent
    arms = json.loads(args.native_report.read_text())["arms"]
    selected = [row for row in arms if (row.get("element"), row.get("xc"), row.get("relativity"), row.get("format"))
                == ("Si", "pbe", "scalar", "upf")]
    if not selected:
        parser.error("the native report has no compatible silicon UPF arm")
    # Freeze reference files and record the solver before running cases.
    inputs = args.output / "inputs"
    inputs.mkdir()
    for case in protocol["benchmarks"]:
        snapshot = inputs / (case["id"] + ".in")
        shutil.copyfile(case["input"], snapshot)
        if design.digest(snapshot) != case["input_sha256"]:
            raise ValueError("benchmark input changed during snapshot")
        case["input"] = str(snapshot)
    shutil.copyfile(args.si_protocol, inputs / "source-protocol.json")
    design.write_json(inputs / "evaluation.json", protocol)
    env = dict(os.environ, OMP_NUM_THREADS="1", OPENBLAS_NUM_THREADS="1", MKL_NUM_THREADS="1")
    env.setdefault("OMPI_MCA_btl", "^uct")
    report = {"scope": "same-family EOS validation for scalar-PBE silicon UPFs",
              "solver_sha256": design.digest(solver), "arms": []}
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        jobs = [pool.submit(assess, arm, native, args.output, protocol, solver, env) for arm in selected]
        for job in as_completed(jobs):
            report["arms"].append(job.result())
            design.write_json(args.output / "report.json", report)


if __name__ == "__main__":
    main()
