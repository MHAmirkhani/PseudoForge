#!/usr/bin/env python3
"""Compare prespecified search strategies on one frozen QE protocol."""
import argparse
import json
from pathlib import Path
import random
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import pf_design as design

STRATEGIES = ("random", "uniform", "adaptive", "bayesian")


def summarize(run, returncode, report):
    if report.get("checkpoint", {}).get("phase") != "complete" or returncode not in (0, 2):
        raise ValueError(f"{run}: design stopped with exit status {returncode}; inspect its report and log")
    costs = report["resource_accounting"]
    return {"strategy": report["search"]["strategy"], "seed": report["search"]["seed"],
            "search_order": report["search"]["trial_order"], "selected": report["selected"],
            "meets_reference_constraints": report["meets_reference_constraints"],
            "elapsed_training_core_hours": costs["training_elapsed_core_hours"],
            "training_cpu_seconds": costs["training_trial_cpu_seconds"], "setup_cpu_seconds": costs["setup_cpu_seconds"],
            "heldout_cpu_seconds": costs.get("heldout_cpu_seconds", 0),
            "worst_heldout_error_ratio": (report["test"] or {}).get("worst_normalized_error")}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("protocol", type=Path)
    parser.add_argument("-o", "--output", type=Path, required=True)
    parser.add_argument("--pw", required=True)
    parser.add_argument("--seeds", type=int, nargs="+", required=True)
    parser.add_argument("--core-hours", type=float, required=True)
    parser.add_argument("--max-trials", type=int)
    args = parser.parse_args()
    budget = design.finite(args.core_hours, "core-hour budget", positive=True)
    if not 0 < budget <= sys.float_info.max / 3600:
        parser.error("core-hour budget cannot be represented in seconds")
    if len(set(args.seeds)) != len(args.seeds) or any(not 0 <= seed < 2**64 for seed in args.seeds):
        parser.error("provide distinct unsigned 64-bit seeds")
    solver = shutil.which(args.pw)
    if not solver:
        parser.error("provide a local pw.x")
    solver = Path(solver).resolve()
    source = args.protocol.resolve(strict=True)
    original = source.read_bytes()
    protocol = design.load_protocol(source)
    if source.read_bytes() != original:
        raise ValueError("protocol changed during validation")
    limit = len(protocol["candidates"]) if args.max_trials is None else args.max_trials
    if not 1 <= limit <= len(protocol["candidates"]):
        parser.error("--max-trials must be within the expanded candidate count")
    output = args.output.resolve()
    output.mkdir()
    archive = output / "protocol-inputs"
    hashes = design.archive_protocol(protocol, original, archive)
    base = json.loads((archive / "protocol.json").read_text())
    for case in base["benchmarks"]:
        case["input"] = str(archive / case["input"])
    base["fixed_pseudos"] = {symbol: str(archive / file) for symbol, file in base["fixed_pseudos"].items()}
    runs = []
    for seed in args.seeds:
        order = list(STRATEGIES)
        random.Random(seed).shuffle(order)
        for strategy in order:
            run = f"{seed}-{strategy}"
            case_protocol = {**base, "search": {"strategy": strategy, "seed": seed, "max_trials": limit,
                                                "training_core_hours": budget}}
            path = output / (run + ".json")
            design.write_json(path, case_protocol)
            design.load_protocol(path)
            runs.append(run)
    manifest = {"scope": "paired local one-logical-CPU training budgets; setup and holdout measured separately",
                "input_sha256": hashes, "solver_sha256": design.digest(solver), "training_core_hours": budget,
                "max_trials": limit, "seeds": args.seeds, "run_order": runs,
                "run_protocol_sha256": {run: design.digest(output / (run + ".json")) for run in runs}}
    design.write_json(output / "comparison-plan.json", manifest)
    evidence = []
    for run in runs:
        path = output / run
        command = [str(ROOT / "pseudoforge"), "design", str(path.with_suffix(".json")),
                   "--pw", str(solver), "-o", str(path)]
        with path.with_suffix(".log").open("w") as log:
            completed = subprocess.run(command, stdout=log, stderr=log)
        report = json.loads((path / "report.json").read_text())
        evidence.append(summarize(run, completed.returncode, report))
        design.write_json(output / "comparison-results.json", {"runs": evidence})
        print(run, evidence[-1]["selected"], evidence[-1]["meets_reference_constraints"], flush=True)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError) as error:
        sys.exit(f"compare search: {error}")
