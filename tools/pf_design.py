#!/usr/bin/env python3
"""Local, reference-constrained pseudopotential search (Python standard library).

Generation stays in the Bash core. QE measures the same physical observables
for every candidate. A candidate is selected using training cases only; held
out cases are evaluated once after that decision and cannot change the choice.
"""
from __future__ import annotations

import argparse
import hashlib
import itertools
import json
import math
import os
import platform
from pathlib import Path
import random
import re
import resource
import shlex
import shutil
import signal
import statistics
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
FLAGS = {
    "config": "--config", "core_hole": "--core-hole", "zed": "--zed",
    "zval": "--zval", "nlcc": "--nlcc", "rcore": "--rcore", "rho0": "--rho0",
    "which_augfun": "--augfun", "rmatch_augfun": "--rmatch", "lloc": "--lloc",
    "rcloc": "--rcloc", "rcut_scale": "--rcut-scale", "nc_form": "--nc-form",
    "beta": "--beta", "tr2": "--tr2", "lsd": "--lsd", "gipaw": "--gipaw",
    "extra_projectors": "--projector", "channel_radii": "--channel-rc", "engine_options": "--engine-option",
}
METRICS = {"force_max_Ry_bohr", "stress_max_kbar", "relative_energy_Ry_atom"}
NUMBER = r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eEdD][-+]?\d+)?"
IDENTIFIER = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,79}$")


def finite(value, label, *, positive=False):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise ValueError(f"{label} must be a finite number")
    if positive and value <= 0:
        raise ValueError(f"{label} must be positive")
    return float(value)


def keys(obj, allowed, label):
    if not isinstance(obj, dict):
        raise ValueError(f"{label} must be an object")
    unknown = obj.keys() - allowed
    if unknown:
        raise ValueError(f"unknown {label} keys: {', '.join(sorted(unknown))}")


def identifier(value, label):
    if not isinstance(value, str) or not IDENTIFIER.fullmatch(value):
        raise ValueError(f"invalid {label}: {value!r}")
    return value


def vector(value, label, rows=None):
    if not isinstance(value, list) or (rows is not None and len(value) != rows):
        raise ValueError(f"{label} has the wrong number of rows")
    result = []
    for row in value:
        if not isinstance(row, list) or len(row) != 3:
            raise ValueError(f"{label} needs three components per row")
        result.extend(finite(x, label) for x in row)
    return result


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def option_args(options):
    keys(options, set(FLAGS), "candidate options")
    result = []
    for key, value in sorted(options.items()):
        if key in ("lsd", "gipaw"):
            if not isinstance(value, bool):
                raise ValueError(f"{key} must be a boolean")
            if value:
                result.append(FLAGS[key])
        elif key in ("channel_radii", "extra_projectors", "engine_options"):
            if not isinstance(value, list) or not value or not all(isinstance(x, str) and x for x in value):
                raise ValueError(f"{key} must be a nonempty list of strings")
            for entry in value:
                result.extend((FLAGS[key], entry))
        elif isinstance(value, bool) or not isinstance(value, (str, int, float)):
            raise ValueError(f"{key} must be a scalar")
        else:
            if isinstance(value, (int, float)):
                finite(value, key)
            if not str(value) or "\n" in str(value) or "\r" in str(value):
                raise ValueError(f"invalid {key}")
            result.extend((FLAGS[key], str(value)))
    return result


def composition(text):
    match = re.search(r"^\s*ATOMIC_POSITIONS[^\n]*\n(.*?)(?=^\s*(?:K_POINTS|CELL_PARAMETERS|ATOMIC_SPECIES|[A-Z_]{3,})\b|\Z)", text, re.M | re.S)
    if not match:
        raise ValueError("benchmark needs an explicit ATOMIC_POSITIONS block")
    symbols = []
    for line in match[1].splitlines():
        line = line.split("!", 1)[0].strip()
        if not line:
            continue
        fields = line.split()
        if len(fields) < 4 or not re.fullmatch(r"[A-Z][a-z]?", fields[0]):
            raise ValueError("invalid ATOMIC_POSITIONS row")
        symbols.append(fields[0])
    return tuple(sorted(symbols))


def convergence_settings(protocol):
    if "convergence" not in protocol:
        return
    check = protocol["convergence"]
    keys(check, {"base_k_mesh", "levels", "tolerance_fraction"}, "convergence")
    def mesh(value):
        if (not isinstance(value, list) or len(value) != 3 or
                any(type(n) is not int or n < 1 for n in value)):
            raise ValueError("a convergence k mesh needs three positive integers")
        return value
    previous_mesh = mesh(check.get("base_k_mesh"))
    fraction = finite(check.get("tolerance_fraction"), "convergence tolerance fraction", positive=True)
    if fraction > 1:
        raise ValueError("convergence tolerance fraction must be at most 1")
    levels = check.get("levels")
    if not isinstance(levels, list) or not 1 <= len(levels) <= 6:
        raise ValueError("provide 1..6 tighter convergence levels")
    for level in levels:
        keys(level, {"ecutwfc", "ecutrho", "k_mesh"}, "convergence level")
        wave = finite(level.get("ecutwfc"), "convergence ecutwfc", positive=True)
        density = finite(level.get("ecutrho"), "convergence ecutrho", positive=True)
        if density < wave:
            raise ValueError("convergence ecutrho must be >= ecutwfc")
        current_mesh = mesh(level.get("k_mesh"))
        if any(a < b for a, b in zip(current_mesh, previous_mesh)):
            raise ValueError("convergence levels cannot coarsen the k mesh")
        previous_mesh = current_mesh
    for candidate in protocol["candidates"]:
        previous = (candidate["ecutwfc"], candidate["ecutrho"], *check["base_k_mesh"])
        for level in levels:
            current = (level["ecutwfc"], level["ecutrho"], *level["k_mesh"])
            if current == previous or any(a < b for a, b in zip(current, previous)):
                raise ValueError("each convergence level must tighten at least one setting without loosening any")
            previous = current


def load_protocol(path):
    def unique(pairs):
        obj = {}
        for key, value in pairs:
            if key in obj:
                raise ValueError(f"duplicate JSON key: {key}")
            obj[key] = value
        return obj

    protocol = json.loads(path.read_text(), object_pairs_hook=unique)
    keys(protocol, {"schema_version", "element", "xc", "relativity", "candidates", "benchmarks", "fixed_pseudos", "repeats", "timeout_seconds", "reference_description", "convergence", "selection", "search"}, "protocol")
    if type(protocol.get("schema_version")) is not int or protocol["schema_version"] != 1:
        raise ValueError("schema_version must be 1")
    if not re.fullmatch(r"[A-Z][a-z]?", str(protocol.get("element", ""))):
        raise ValueError("element must be one chemical symbol")
    identifier(protocol.get("xc"), "XC")
    if protocol.get("relativity") not in ("nonrel", "scalar", "full"):
        raise ValueError("relativity must be nonrel, scalar or full")
    if protocol.get("selection", "cost") not in ("cost", "accuracy"):
        raise ValueError("selection must be cost or accuracy")
    for key, default, maximum in (("repeats", 3, 20), ("timeout_seconds", 600, 86400)):
        value = protocol.get(key, default)
        if isinstance(value, bool) or not isinstance(value, int) or not 1 <= value <= maximum:
            raise ValueError(f"{key} must be an integer in 1..{maximum}")
        protocol[key] = value
    candidates = protocol.get("candidates")
    if not isinstance(candidates, list) or not candidates or len(candidates) > 256:
        raise ValueError("provide 1..256 candidate definitions")
    expanded, names = [], set()
    for candidate in candidates:
        keys(candidate, {"id", "engine", "family", "profile", "options", "grid", "ecutwfc", "ecutrho"}, "candidate")
        name = identifier(candidate.get("id"), "candidate id")
        for key in ("engine", "profile"):
            identifier(candidate.get(key), key)
        if candidate.get("family") not in ("nc", "us", "paw"):
            raise ValueError("candidate family must be nc, us or paw")
        for key in ("ecutwfc", "ecutrho"):
            finite(candidate.get(key), key, positive=True)
        if candidate["ecutrho"] < candidate["ecutwfc"]:
            raise ValueError("ecutrho must be >= ecutwfc")
        options = candidate.get("options", {})
        option_args(options)
        grid = candidate.get("grid", {})
        keys(grid, set(FLAGS), "grid")
        if set(options) & set(grid):
            raise ValueError("an option cannot appear in both options and grid")
        size = 1
        for values in grid.values():
            if not isinstance(values, list) or not values:
                raise ValueError("each grid parameter needs a nonempty list")
            size *= len(values)
        if size + len(expanded) > 256:
            raise ValueError("expanded candidate grid exceeds 256; narrow the search")
        for index, values in enumerate(itertools.product(*grid.values())):
            item = dict(candidate)
            item["id"] = name if not grid else f"{name}-{index + 1:03d}"
            if item["id"] in names:
                raise ValueError("candidate ids must be unique")
            names.add(item["id"])
            item["options"] = {**options, **dict(zip(grid, values))}
            option_args(item["options"])
            expanded.append(item)
    protocol["candidates"] = expanded
    convergence_settings(protocol)
    if "search" in protocol:
        search = protocol["search"]
        keys(search, {"strategy", "seed", "max_trials"}, "search")
        if search.get("strategy") != "random":
            raise ValueError("search strategy must be random")
        if type(search.get("seed")) is not int or not 0 <= search["seed"] < 2**64:
            raise ValueError("random search requires an unsigned 64-bit seed")
        if type(search.get("max_trials")) is not int or not 1 <= search["max_trials"] <= len(expanded):
            raise ValueError("max_trials must be between 1 and the expanded candidate count")
    fixed = protocol.get("fixed_pseudos", {})
    if not isinstance(fixed, dict):
        raise ValueError("fixed_pseudos must map symbols to local UPF paths")
    protocol["fixed_pseudos"] = {}
    for symbol, file in fixed.items():
        if not re.fullmatch(r"[A-Z][a-z]?", symbol) or symbol == protocol["element"] or not isinstance(file, str):
            raise ValueError("invalid fixed_pseudos entry")
        file = (path.parent / file).resolve(strict=True)
        if not file.is_file():
            raise ValueError("fixed pseudopotential must be a file")
        protocol["fixed_pseudos"][symbol] = str(file)
    cases = protocol.get("benchmarks")
    if not isinstance(cases, list) or not 2 <= len(cases) <= 200:
        raise ValueError("provide 2..200 benchmark cases with train and test splits")
    case_ids, environments, groups = set(), {}, {}
    for case in cases:
        keys(case, {"id", "split", "group", "input", "reference", "tolerances", "relative_to"}, "benchmark")
        name = identifier(case.get("id"), "benchmark id")
        if name in case_ids:
            raise ValueError("benchmark ids must be unique")
        case_ids.add(name)
        if case.get("split") not in ("train", "test"):
            raise ValueError("benchmark split must be train or test")
        if "group" in case:
            group = identifier(case["group"], "benchmark group")
            if groups.setdefault(group, case["split"]) != case["split"]:
                raise ValueError(f"benchmark group {group} appears in both train and test splits")
        if not isinstance(case.get("input"), str):
            raise ValueError("benchmark input must be a local template path")
        file = (path.parent / case["input"]).resolve(strict=True)
        text = file.read_text()
        for token in ("{{PSEUDO_DIR}}", "{{UPF}}", "{{ECUTWFC}}", "{{ECUTRHO}}", "{{OUTDIR}}", "{{PREFIX}}"):
            if token not in text:
                raise ValueError(f"{name}: missing template token {token}")
        mesh_token = re.search(r"^\s*K_POINTS\s+automatic[ \t]*\r?\n[ \t]*{{K_MESH}}[ \t]+[01][ \t]+[01][ \t]+[01][ \t]*$", text, re.M | re.I)
        if "convergence" in protocol:
            if not mesh_token or text.count("{{K_MESH}}") != 1:
                raise ValueError(f"{name}: convergence needs K_POINTS automatic with {{{{K_MESH}}}} followed by three shifts")
        elif "{{K_MESH}}" in text:
            raise ValueError(f"{name}: {{{{K_MESH}}}} requires a convergence specification")
        if not re.search(r"\bcalculation\s*=\s*['\"]scf['\"]", text, re.I):
            raise ValueError(f"{name}: benchmarks must be single-point SCF calculations")
        if "input_dft" in text.lower():
            raise ValueError(f"{name}: do not override the generated functional with input_dft")
        comp = composition(text)
        if protocol["element"] not in comp or set(comp) - {protocol["element"]} - fixed.keys():
            raise ValueError(f"{name}: missing fixed pseudopotentials for its composition")
        nat_match = re.search(r"\bnat\s*=\s*(\d+)", text, re.I)
        if not nat_match or int(nat_match[1]) != len(comp):
            raise ValueError(f"{name}: nat disagrees with ATOMIC_POSITIONS")
        species_match = re.search(r"^\s*ATOMIC_SPECIES\s*\n(.*?)(?=^\s*(?:ATOMIC_POSITIONS|K_POINTS|CELL_PARAMETERS)\b|\Z)", text, re.M | re.S)
        species = {}
        if species_match:
            for row in species_match[1].splitlines():
                fields = row.split("!", 1)[0].split()
                if not fields:
                    continue
                if len(fields) != 3 or fields[0] in species:
                    raise ValueError(f"{name}: invalid or duplicate ATOMIC_SPECIES row")
                try:
                    mass = float(fields[1])
                except ValueError as exc:
                    raise ValueError(f"{name}: invalid species mass") from exc
                finite(mass, "atomic mass", positive=True)
                expected = "{{UPF}}" if fields[0] == protocol["element"] else fields[0] + ".fixed.UPF"
                if fields[2] != expected:
                    raise ValueError(f"{name}: species must use generated {{{{UPF}}}} or SYMBOL.fixed.UPF")
                species[fields[0]] = fields[2]
        ntyp_match = re.search(r"\bntyp\s*=\s*(\d+)", text, re.I)
        if set(species) != set(comp) or not ntyp_match or int(ntyp_match[1]) != len(species):
            raise ValueError(f"{name}: ATOMIC_SPECIES/ntyp disagrees with its composition")
        case["input"] = str(file)
        case["composition"] = comp
        case["input_sha256"] = digest(file)
        fingerprint = re.sub(r"!.*", "", text).strip()
        if fingerprint in environments and environments[fingerprint] != case["split"]:
            raise ValueError("the same input appears in both train and test splits")
        environments[fingerprint] = case["split"]
        ref = case.get("reference")
        keys(ref, {"source", "kind", "xc", "relativity", "energy_Ry", "forces_Ry_bohr", "stress_kbar"}, "reference")
        if not isinstance(ref.get("source"), str) or not ref["source"].strip():
            raise ValueError("every reference needs a source citation or identifier")
        if ref.get("kind") not in ("all-electron", "converged-pseudopotential", "synthetic-test"):
            raise ValueError("reference kind must identify all-electron, converged-pseudopotential or synthetic-test")
        if ref.get("xc") != protocol["xc"] or ref.get("relativity") != protocol["relativity"]:
            raise ValueError("reference XC and relativity must match the generation specification")
        tolerances = case.get("tolerances")
        keys(tolerances, METRICS, "tolerances")
        if not tolerances:
            raise ValueError("every case needs at least one measured constraint")
        for metric, tolerance in tolerances.items():
            finite(tolerance, metric, positive=True)
            if metric == "force_max_Ry_bohr":
                vector(ref.get("forces_Ry_bohr"), "reference forces", len(comp))
                if not re.search(r"tprnfor\s*=\s*\.true\.", text, re.I):
                    raise ValueError("force benchmarks need tprnfor=.true.")
            elif metric == "stress_max_kbar":
                vector(ref.get("stress_kbar"), "reference stress", 3)
                if not re.search(r"tstress\s*=\s*\.true\.", text, re.I):
                    raise ValueError("stress benchmarks need tstress=.true.")
            else:
                finite(ref.get("energy_Ry"), "reference energy")
                identifier(case.get("relative_to"), "relative energy anchor")
    by_id = {c["id"]: c for c in cases}
    for case in cases:
        if "relative_energy_Ry_atom" in case["tolerances"]:
            anchor = by_id.get(case["relative_to"])
            if not anchor or anchor is case or anchor["split"] != case["split"] or anchor["composition"] != case["composition"]:
                raise ValueError("energy anchor must be a different case with the same composition and split")
            if case.get("group") != anchor.get("group"):
                raise ValueError("energy anchor must belong to the same declared benchmark group")
            finite(anchor["reference"].get("energy_Ry"), "anchor reference energy")
    if {c["split"] for c in cases} != {"train", "test"}:
        raise ValueError("both train and held-out test cases are required")
    return protocol


def generation_args(protocol, candidate, output):
    return [str(ROOT / "pseudoforge"), "generate", "-e", protocol["element"], "-x", protocol["xc"],
            "-r", protocol["relativity"], "-t", candidate["family"], "-p", candidate["profile"],
            "--engine", candidate["engine"], "--format", "upf", "--source", "local",
            "--no-autofix", "-j", "1", *option_args(candidate["options"]), "-o", str(output)]


def parse_qe(text, nat):
    if "JOB DONE." not in text or "convergence NOT achieved" in text:
        raise ValueError("QE did not finish a converged SCF calculation")
    match = re.findall(r"!\s+total energy\s*=\s*(" + NUMBER + r")\s+Ry", text)
    if not match:
        raise ValueError("no converged total energy in QE output")
    number = lambda x: float(x.replace("D", "e").replace("d", "e"))
    energy = number(match[-1])
    forces = re.findall(r"atom\s+\d+\s+type\s+\d+\s+force\s*=\s*(" + NUMBER + r")\s+(" + NUMBER + r")\s+(" + NUMBER + r")", text)
    forces = [[number(x) for x in row] for row in forces[-nat:]] if len(forces) >= nat else None
    stress = None
    blocks = re.findall(r"total\s+stress[^\n]*\n([^\n]+)\n([^\n]+)\n([^\n]+)", text, re.I)
    if blocks:
        rows = [re.findall(NUMBER, row) for row in blocks[-1]]
        if all(len(row) == 6 for row in rows):
            stress = [[number(x) for x in row[3:]] for row in rows]
    result = {"energy_Ry": energy, "forces_Ry_bohr": forces, "stress_kbar": stress}
    numbers = [energy] + [x for data in (forces, stress) if data is not None for row in data for x in row]
    if not all(math.isfinite(x) for x in numbers):
        raise ValueError("nonfinite value in QE output")
    return result


def measure_errors(case, result, all_results, by_id):
    errors = {}
    for metric in case["tolerances"]:
        if metric == "relative_energy_Ry_atom":
            anchor = case["relative_to"]
            delta = result["energy_Ry"] - all_results[anchor]["energy_Ry"]
            reference_delta = case["reference"]["energy_Ry"] - by_id[anchor]["reference"]["energy_Ry"]
            errors[metric] = abs(delta - reference_delta) / len(case["composition"])
        else:
            key = "forces_Ry_bohr" if metric == "force_max_Ry_bohr" else "stress_kbar"
            rows = len(case["composition"]) if key == "forces_Ry_bohr" else 3
            actual = vector(result.get(key), key, rows)
            expected = vector(case["reference"][key], key, rows)
            errors[metric] = max(abs(a - b) for a, b in zip(actual, expected))
    return errors


def write_json(path, value):
    # Replacing one file prevents an interrupted update from corrupting it.
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, allow_nan=False) + "\n")
    temporary.replace(path)


def child_cpu_seconds():
    usage = resource.getrusage(resource.RUSAGE_CHILDREN)
    return usage.ru_utime + usage.ru_stime


def execute(command, directory, logfile, env, timeout, stdin=None):
    started = time.perf_counter()
    with logfile.open("wb") as log:
        process = subprocess.Popen(command, cwd=directory, env=env, stdin=subprocess.PIPE if stdin is not None else subprocess.DEVNULL,
                                   stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            process.communicate(input=stdin, timeout=timeout)
        except subprocess.TimeoutExpired as exc:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
            raise ValueError(f"command timed out; see {logfile}") from exc
    if process.returncode:
        raise ValueError(f"command exited {process.returncode}; see {logfile}")
    return time.perf_counter() - started


def run_cases(protocol, candidate, project, cases, pw, env, *, level=None, index=0):
    # Every repeat has a distinct scratch directory. No candidate benefits
    # from another candidate's wavefunctions or a previous test's restart.
    by_id = {case["id"]: case for case in cases}
    all_measurements, elapsed = {}, []
    upfs = [p for p in (project / "pseudos").iterdir() if p.suffix.lower() == ".upf" and not p.name.endswith(".fixed.UPF")]
    if len(upfs) != 1:
        raise ValueError("design requires exactly one generated UPF")
    numerical = candidate if level is None else level
    k_mesh = level["k_mesh"] if level is not None else protocol.get("convergence", {}).get("base_k_mesh")
    directory = "benchmarks" if not index else f"convergence-{index}"
    for case in cases:
        measurements, durations = [], []
        text = Path(case["input"]).read_text()
        for repeat in range(protocol["repeats"] if not index else 1):
            folder = project / directory / case["id"] / str(repeat + 1)
            folder.mkdir(parents=True)
            scratch = folder / "scratch"
            scratch.mkdir()
            substitutions = {"PSEUDO_DIR": str(project / "pseudos"), "UPF": upfs[0].name,
                             "ECUTWFC": str(numerical["ecutwfc"]), "ECUTRHO": str(numerical["ecutrho"]),
                             "OUTDIR": str(scratch), "PREFIX": "pf_design", "ELEMENT": protocol["element"]}
            if k_mesh is not None:
                substitutions["K_MESH"] = " ".join(map(str, k_mesh))
            rendered = text
            for key, value in substitutions.items():
                rendered = rendered.replace("{{" + key + "}}", value)
            if re.search(r"{{[^}]+}}", rendered):
                raise ValueError("unresolved input template token")
            (folder / "input.in").write_text(rendered)
            logfile = folder / "output.out"
            durations.append(execute([pw], folder, logfile, env, protocol["timeout_seconds"], rendered.encode()))
            measurements.append(parse_qe(logfile.read_text(errors="replace"), len(case["composition"])))
        # Single-point calculations must be reproducible within their own
        # stated tolerances; use the worst error over repeats, never the best.
        all_measurements[case["id"]] = measurements
        elapsed.append(statistics.median(durations))
    evaluated, worst = [], 0.0
    for case in cases:
        errors = {key: 0.0 for key in case["tolerances"]}
        for repeat in range(len(all_measurements[case["id"]])):
            samples = {key: values[repeat] for key, values in all_measurements.items()}
            observed = measure_errors(case, samples[case["id"]], samples, by_id)
            for metric, value in observed.items():
                errors[metric] = max(errors[metric], value)
        ratio = max(errors[key] / case["tolerances"][key] for key in errors)
        worst = max(worst, ratio)
        entry = {"id": case["id"], "errors": errors, "tolerances": case["tolerances"],
                 "passes": ratio <= 1.0, "measurements": all_measurements[case["id"]]}
        if "group" in case:
            entry["group"] = case["group"]
        evaluated.append(entry)
    return {"cases": evaluated, "cost_seconds": sum(elapsed), "worst_normalized_error": worst,
            "passes": worst <= 1.0}


def numerical_drift(cases, earlier, later, fraction):
    """Compare the actual observables, including the signed relative energies."""
    by_id = {case["id"]: case for case in cases}
    last = {case["id"]: case["measurements"][0] for case in later["cases"]}
    samples = {case["id"]: case["measurements"] for case in earlier["cases"]}
    errors = {}
    for repeat in range(len(next(iter(samples.values())))):
        first = {name: values[repeat] for name, values in samples.items()}
        reference = {name: {**case, "reference": first[name]} for name, case in by_id.items()}
        for name, case in reference.items():
            observed = measure_errors(case, last[name], last, reference)
            error = errors.setdefault(name, {})
            for metric, value in observed.items():
                error[metric] = max(value, error.get(metric, 0.0))
    worst = max((value / by_id[name]["tolerances"][metric]) / fraction
                for name, metrics in errors.items() for metric, value in metrics.items())
    return {"changes": errors, "worst_normalized_drift": worst, "passes": worst <= 1}


def evaluate(protocol, candidate, project, cases, pw, env):
    result = run_cases(protocol, candidate, project, cases, pw, env)
    if "convergence" not in protocol:
        return result
    check = protocol["convergence"]
    result["reference_passes"] = result["passes"]
    result["convergence"] = {"passes": False, "levels": []}
    record = result["convergence"]
    previous = result
    for index, settings in enumerate(check["levels"], start=1):
        try:
            assessed = run_cases(protocol, candidate, project, cases, pw, env, level=settings, index=index)
            fraction = check["tolerance_fraction"]
            entry = {"settings": settings, "assessment": assessed,
                     "from_previous": numerical_drift(cases, previous, assessed, fraction),
                     "from_base": numerical_drift(cases, result, assessed, fraction)}
        except (ValueError, OSError) as exc:
            record["levels"].append({"settings": settings, "error": str(exc)})
            result["passes"] = False
            return result
        record["levels"].append(entry)
        previous = assessed
    record["passes"] = all(level["from_previous"]["passes"] and level["from_base"]["passes"]
                           for level in record["levels"])
    result["passes"] = result["reference_passes"] and record["passes"] and all(
        level["assessment"]["passes"] for level in record["levels"])
    return result


def pareto(results):
    feasible = [r for r in results if r.get("training", {}).get("passes")]
    objectives = lambda r: (r["training"]["cost_seconds"], r["training"]["worst_normalized_error"])
    return [r["id"] for r in feasible if not any(
        all(a <= b for a, b in zip(objectives(other), objectives(r))) and
        any(a < b for a, b in zip(objectives(other), objectives(r))) for other in feasible)]


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("protocol", type=Path)
    parser.add_argument("-o", "--output", type=Path, required=True)
    parser.add_argument("--plan", action="store_true", help="validate the protocol and engine controls without running solvers")
    parser.add_argument("--pw", default=os.environ.get("PW_BIN", "pw.x"), help="QE pw.x executable (no shell launcher)")
    args = parser.parse_args(argv)
    protocol_path = args.protocol.resolve(strict=True)
    protocol = load_protocol(protocol_path)
    output = args.output.resolve()
    if "'" in str(output) or "\n" in str(output) or "\r" in str(output):
        raise ValueError("output path cannot contain apostrophes or newlines because QE consumes it as a Fortran path")
    if output.exists() and (not output.is_dir() or any(output.iterdir())):
        raise ValueError("output must be a new or empty directory; existing runs are never removed")
    # Query real CLI capabilities before creating a project or launching any
    # generator. Proxies cannot stand in for the reference XC in a design run.
    response = subprocess.run([str(ROOT / "pseudoforge"), "api", "GET", "/api/xc"], capture_output=True, text=True, check=True, timeout=30)
    functionals = json.loads(response.stdout)
    found = next((item for item in functionals if item["id"] == protocol["xc"]), None)
    if not found or found.get("status") == "proxy":
        raise ValueError("design requires a native XC functional; functional proxies cannot match its references")
    commands = []
    for candidate in protocol["candidates"]:
        command = generation_args(protocol, candidate, output / candidate["id"])
        checked = subprocess.run([str(ROOT / "pseudoforge"), "build-command", *command[2:]], capture_output=True, text=True, timeout=60)
        if checked.returncode:
            raise ValueError(f"{candidate['id']}: unsupported generation settings: {checked.stderr.strip()}")
        commands.append(command)
    output.mkdir(parents=True, exist_ok=True)
    archive = output / "protocol-inputs"
    archive.mkdir()
    (archive / "original.json").write_bytes(protocol_path.read_bytes())
    for case in protocol["benchmarks"]:
        snapshot = archive / (case["id"] + ".in")
        shutil.copyfile(case["input"], snapshot)
        if digest(snapshot) != case["input_sha256"]:
            raise ValueError("a benchmark changed during validation; repeat with immutable inputs")
        case["input"] = str(snapshot)
    for symbol, file in protocol["fixed_pseudos"].items():
        snapshot = archive / (symbol + ".fixed.UPF")
        shutil.copyfile(file, snapshot)
        protocol["fixed_pseudos"][symbol] = str(snapshot)
    portable = json.loads(json.dumps(protocol))
    for case in portable["benchmarks"]:
        case["input"] = Path(case["input"]).name
        case.pop("composition")
        case.pop("input_sha256")
    for candidate in portable["candidates"]:
        candidate.pop("grid", None)
    portable["fixed_pseudos"] = {symbol: Path(file).name for symbol, file in protocol["fixed_pseudos"].items()}
    write_json(archive / "protocol.json", portable)
    report = {"schema_version": 1, "protocol_sha256": digest(protocol_path), "selection_uses": "train only",
              "selection_objective": protocol.get("selection", "cost"),
              "frozen_protocol_sha256": digest(archive / "protocol.json"),
              "host": {"platform": platform.platform(), "machine": platform.machine(), "python": platform.python_version(), "threads": 1},
              "reference_description": protocol.get("reference_description", ""),
              "verification_scope": "only the supplied cases, reference theory and tolerances; no guarantee for other materials",
              "reference_kinds": sorted({case["reference"]["kind"] for case in protocol["benchmarks"]}),
              "solver": None, "results": [], "selected": None, "pareto": [], "test": None,
              "meets_reference_constraints": False, "plan_only": args.plan,
              "commands": [shlex.join(command) for command in commands],
              "fixed_pseudos": {el: {"path": file, "sha256": digest(file)} for el, file in protocol["fixed_pseudos"].items()}}
    trials = list(zip(protocol["candidates"], commands))
    search = protocol.get("search", {"strategy": "grid", "max_trials": len(trials)})
    if search["strategy"] == "random":
        trials.sort(key=lambda trial: trial[0]["id"])
        random.Random(search["seed"]).shuffle(trials)
        trials = trials[:search["max_trials"]]
    report["search"] = {**search, "trial_order": [candidate["id"] for candidate, _ in trials],
                        "candidate_count": len(commands)}
    write_json(output / "report.json", report)
    if args.plan:
        env = dict(os.environ)
        previews = []
        for candidate, command in trials:
            preview = output / "previews" / candidate["id"]
            command = command[:-1] + [str(preview), "--dry-run"]
            execute(command, ROOT, output / (candidate["id"] + ".preview.log"), env, protocol["timeout_seconds"])
            previews.append({"id": candidate["id"], "project": str(preview)})
        report["previews"] = previews
        write_json(output / "report.json", report)
        print(f"Validated {len(commands)} candidates and {len(protocol['benchmarks'])} cases; planned trials: {len(trials)}; report: {output / 'report.json'}")
        return 0
    pw = shutil.which(args.pw)
    if not pw:
        raise ValueError("pw.x not found; specify --pw /absolute/path/to/pw.x")
    report["solver"] = {"path": str(Path(pw).resolve()), "sha256": digest(pw)}
    env = dict(os.environ, OMP_NUM_THREADS="1", OPENBLAS_NUM_THREADS="1", MKL_NUM_THREADS="1")
    env.setdefault("OMPI_MCA_btl", "^uct")
    train = [case for case in protocol["benchmarks"] if case["split"] == "train"]
    heldout = [case for case in protocol["benchmarks"] if case["split"] == "test"]
    report["resource_accounting"] = {
        "scope": "elapsed time and CPU time reported by the OS for reaped local child processes",
        "generation_cpu_seconds": 0.0, "training_trial_cpu_seconds": 0.0,
        "training_trial_wall_seconds": 0.0,
    }
    accounting = report["resource_accounting"]
    for candidate, command in trials:
        item = {"id": candidate["id"], "candidate": candidate, "status": "failed"}
        project = output / candidate["id"]
        started = time.perf_counter()
        cpu_started = child_cpu_seconds()
        try:
            try:
                execute(command, ROOT, output / (candidate["id"] + ".generation.log"), env, protocol["timeout_seconds"])
            finally:
                item["generation_wall_seconds"] = time.perf_counter() - started
                item["generation_cpu_seconds"] = child_cpu_seconds() - cpu_started
            for symbol, file in protocol["fixed_pseudos"].items():
                shutil.copyfile(file, project / "pseudos" / (symbol + ".fixed.UPF"))
            # The generated UPF is selected independently of fixed species.
            item["training"] = evaluate(protocol, candidate, project, train, pw, env)
            item["status"] = "evaluated"
        except (ValueError, OSError) as exc:
            item["error"] = str(exc)
        item["trial_wall_seconds"] = time.perf_counter() - started
        item["trial_cpu_seconds"] = child_cpu_seconds() - cpu_started
        accounting["generation_cpu_seconds"] += item["generation_cpu_seconds"]
        accounting["training_trial_cpu_seconds"] += item["trial_cpu_seconds"]
        accounting["training_trial_wall_seconds"] += item["trial_wall_seconds"]
        report["results"].append(item)
        write_json(output / "report.json", report)
        print(candidate["id"], item["status"], flush=True)
    report["pareto"] = pareto(report["results"])
    feasible = [item for item in report["results"] if item.get("training", {}).get("passes")]
    if feasible:
        criteria = ("cost_seconds", "worst_normalized_error")
        if report["selection_objective"] == "accuracy":
            criteria = tuple(reversed(criteria))
        winner = min(feasible, key=lambda item: (*(item["training"][key] for key in criteria), item["id"]))
        report["selected"] = winner["id"]
        # Commit the decision to disk before opening any held-out calculation.
        write_json(output / "report.json", report)
        started = time.perf_counter()
        cpu_started = child_cpu_seconds()
        try:
            report["test"] = evaluate(protocol, winner["candidate"], output / winner["id"], heldout, pw, env)
            report["meets_reference_constraints"] = report["test"]["passes"] and "synthetic-test" not in report["reference_kinds"]
        except (ValueError, OSError) as exc:
            report["test"] = {"passes": False, "error": str(exc)}
        finally:
            accounting["heldout_cpu_seconds"] = child_cpu_seconds() - cpu_started
            accounting["heldout_wall_seconds"] = time.perf_counter() - started
    write_json(output / "report.json", report)
    print(f"Selected using training data: {report['selected'] or 'none'}; report: {output / 'report.json'}")
    return 0 if report["meets_reference_constraints"] else 2


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        print(f"design: {error}", file=sys.stderr)
        sys.exit(1)
