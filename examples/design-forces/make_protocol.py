#!/usr/bin/env python3
"""Build an independent all-electron molecular force pilot for PseudoForge."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import shutil
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import pf_design as design

GEOMETRIES = {
    "silane": [("Si", (0., 0., 0.)), ("H", (1.78, 1.65, 1.65)), ("H", (1.65, -1.65, -1.65)),
               ("H", (-1.65, 1.65, -1.65)), ("H", (-1.65, -1.65, 1.65))],
    "silanone": [("Si", (0., 0., 0.)), ("O", (2.95, .10, 0.)),
                 ("H", (-1.30, 2.45, 0.)), ("H", (-1.40, -2.43, .06))],
}
BASIS = ({"Si": "cc-pcvtz", "O": "cc-pcvtz", "H": "cc-pvtz"},
         {"Si": "cc-pcvqz", "O": "cc-pcvqz", "H": "cc-pvqz"},
         {"Si": "cc-pcv5z", "O": "cc-pcv5z", "H": "cc-pv5z"})
AUX_BASIS = "def2-universal-jkfit"


def reference_values(pyscf, geometry, basis, grid, *, gradient, density_fit=True):
    started = time.monotonic()
    elements = sorted({symbol for symbol, _ in geometry})
    mol = pyscf.gto.M(atom=geometry, unit="Bohr", charge=0, spin=0,
                      basis={symbol: basis[symbol] for symbol in elements}, verbose=0, max_memory=768)
    if mol.nelectron != sum(pyscf.gto.charge(symbol) for symbol, _ in geometry):
        raise ValueError("reference must include all electrons")
    calc = pyscf.dft.RKS(mol).sfx2c1e()
    if density_fit:
        calc = calc.density_fit(auxbasis=AUX_BASIS)
    calc.xc = "pbe,pbe"
    calc.grids.level = grid
    calc.conv_tol = 1e-11
    energy = float(calc.kernel())
    if not calc.converged or not math.isfinite(energy):
        raise ValueError("all-electron SCF failed")
    row = {"energy_Ha": energy, "basis": {symbol: basis[symbol] for symbol in elements},
           "auxiliary_basis": AUX_BASIS if density_fit else None, "grid_level": grid}
    if gradient:
        forces = -2 * calc.nuc_grad_method().kernel()  # Hartree to Rydberg, and gradient to force
        if not all(math.isfinite(float(v)) for v in forces.flat):
            raise ValueError("nonfinite all-electron gradient")
        row["forces_Ry_bohr"] = forces.tolist()
    row["wall_seconds"] = time.monotonic() - started
    return row


def force_difference(left, right):
    return max(abs(a - b) for l, r in zip(left, right) for a, b in zip(l, r))


def get_reference(pyscf, name, geometry, allowed_drift, prior=None):
    levels = list(prior or [])

    def measure(basis, grid, density_fit):
        values = reference_values(pyscf, geometry, basis, grid, gradient=True, density_fit=density_fit)
        levels.append(values)
        print(f"{name}: {basis['Si']}, grid {grid}, density fitting {density_fit}", flush=True)

    if not levels:
        for basis, grid, density_fit in ((BASIS[0], 4, False), (BASIS[0], 4, True),
                                         (BASIS[1], 4, True), (BASIS[1], 5, True)):
            measure(basis, grid, density_fit)
    initial_basis_drift = force_difference(levels[1]["forces_Ry_bohr"], levels[2]["forces_Ry_bohr"])
    if initial_basis_drift > allowed_drift and len(levels) == 4:
        measure(BASIS[2], 4, True)
        measure(BASIS[2], 5, True)
    basis_index = 2 if len(levels) == 6 else 1
    previous_basis_level = basis_index
    final = levels[-1]["forces_Ry_bohr"]
    step = .001
    finite_difference = []
    for shift in (-step, step):
        shifted = list(geometry)
        symbol, (x, y, z) = shifted[1]
        shifted[1] = (symbol, (x + shift, y, z))
        finite_difference.append(reference_values(pyscf, shifted, BASIS[basis_index], 5, gradient=False)["energy_Ha"])
    fd_force = -(finite_difference[1] - finite_difference[0]) / step
    return {
        "coordinates_bohr": [[symbol, list(coords)] for symbol, coords in geometry], "levels": levels,
        "density_fit_drift_Ry_bohr": force_difference(levels[0]["forces_Ry_bohr"], levels[1]["forces_Ry_bohr"]),
        "initial_basis_drift_Ry_bohr": initial_basis_drift,
        "basis_drift_Ry_bohr": force_difference(levels[previous_basis_level]["forces_Ry_bohr"], levels[-2]["forces_Ry_bohr"]),
        "grid_drift_Ry_bohr": force_difference(levels[-2]["forces_Ry_bohr"], final),
        "translation_residual_Ry_bohr": max(abs(sum(component)) for component in zip(*final)),
        "finite_difference": {"step_bohr": step, "atom_index": 1, "component": "x",
                              "energy_Ha": finite_difference, "force_Ry_bohr": fd_force,
                              "drift_Ry_bohr": abs(fd_force - final[1][0])},
    }


def input_template(geometry, box):
    species = {"Si": (28.0855, "{{UPF}}"), "O": (15.999, "O.fixed.UPF"), "H": (1.00784, "H.fixed.UPF")}
    elements = sorted({symbol for symbol, _ in geometry})
    atoms = "".join(f"{s} " + " ".join(f"{v + box / 2:.9f}" for v in xyz) + "\n" for s, xyz in geometry)
    species_lines = "".join(f"{s} {species[s][0]} {species[s][1]}\n" for s in elements)
    return f"""&CONTROL
 calculation='scf', pseudo_dir='{{{{PSEUDO_DIR}}}}', outdir='{{{{OUTDIR}}}}',
 prefix='{{{{PREFIX}}}}', disk_io='none', tprnfor=.true.
/
&SYSTEM
 ibrav=1, celldm(1)={box}, nat={len(geometry)}, ntyp={len(elements)},
 ecutwfc={{{{ECUTWFC}}}}, ecutrho={{{{ECUTRHO}}}}, assume_isolated='mt',
 occupations='fixed', nosym=.true.
/
&ELECTRONS
 conv_thr=1e-10, mixing_beta=0.4
/
ATOMIC_SPECIES
{species_lines}ATOMIC_POSITIONS bohr
{atoms}K_POINTS gamma
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("-o", "--output", type=Path, required=True)
    parser.add_argument("--h-upf", type=Path, required=True)
    parser.add_argument("--o-upf", type=Path, required=True)
    source = parser.add_mutually_exclusive_group()
    source.add_argument("--reuse-reference", type=Path, help="validated force-reference.json generated by this example")
    source.add_argument("--refine-reference", type=Path, help="add the five-zeta rung to a saved incomplete reference")
    parser.add_argument("--cell-bohr", type=float, default=18)
    parser.add_argument("--force-tolerance", type=float, default=.008, help="maximum force component error in Ry/bohr")
    args = parser.parse_args()
    box = design.finite(args.cell_bohr, "cell length", positive=True)
    tol = design.finite(args.force_tolerance, "force tolerance", positive=True)
    if box <= 4 * max(abs(x) for geometry in GEOMETRIES.values() for _, xyz in geometry for x in xyz):
        parser.error("isolated cell is too small for the supplied geometries")
    output = args.output
    output.mkdir()
    saved = args.reuse_reference or args.refine_reference
    reference = json.loads(saved.read_text()) if saved else {}
    if saved and (reference.get("schema_version") != 1 or reference.get("method") != "all-electron PBE/sf-X2C-1e"):
        raise ValueError("invalid molecular force reference")
    if not args.reuse_reference:
        import pyscf
        from pyscf import dft, gto, lib  # load optional reference backend only when computing
        lib.num_threads(1)
        hashes = {f"{name}:{element}": hashlib.sha256(json.dumps(gto.basis.load(name, element)).encode()).hexdigest()
                  for basis in (*BASIS, dict.fromkeys(("Si", "O", "H"), AUX_BASIS)) for element, name in basis.items()}
        if saved and (reference["pyscf_version"] != pyscf.__version__ or
                      any(hashes.get(key) != value for key, value in reference["basis_sha256"].items())):
            raise ValueError("saved PySCF or basis identity differs from the current reference backend")
        reference = {"schema_version": 1, "method": "all-electron PBE/sf-X2C-1e", "pyscf_version": pyscf.__version__,
                     "basis_sha256": hashes, "cases": reference.get("cases", {})}
        for name, geometry in GEOMETRIES.items():
            prior = reference["cases"].get(name)
            if prior and prior["coordinates_bohr"] != [[symbol, list(coords)] for symbol, coords in geometry]:
                raise ValueError(f"{name}: reference geometry does not match")
            if not prior or prior["basis_drift_Ry_bohr"] > tol / 4:
                reference["cases"][name] = get_reference(pyscf, name, geometry, tol / 4,
                                                        prior["levels"] if prior else None)
                print(name, "reference calculated", flush=True)
            design.write_json(output / "force-reference.json", reference)
    reference_path = output / "force-reference.json"
    design.write_json(reference_path, reference)
    if reference["schema_version"] != 1 or reference["method"] != "all-electron PBE/sf-X2C-1e":
        raise ValueError("invalid molecular force reference")
    benchmarks = []
    for split, (name, geometry) in zip(("train", "test"), GEOMETRIES.items()):
        case = reference["cases"][name]
        if case["coordinates_bohr"] != [[symbol, list(coords)] for symbol, coords in geometry]:
            raise ValueError(f"{name}: reference geometry does not match")
        uncertainty = max(design.finite(value, f"{name} numerical drift") for value in
                          (case["density_fit_drift_Ry_bohr"], case["basis_drift_Ry_bohr"], case["grid_drift_Ry_bohr"],
                           case["translation_residual_Ry_bohr"], case["finite_difference"]["drift_Ry_bohr"]))
        if uncertainty > tol / 4:
            raise ValueError(f"{name}: numerical reference check exceeds {tol / 4:g} Ry/bohr; inspect {reference_path}")
        template = output / (name + ".in")
        template.write_text(input_template(geometry, box))
        benchmarks.append({"id": name, "input": template.name, "group": name, "split": split,
                           "reference": {"kind": "all-electron", "xc": "pbe", "relativity": "scalar",
                                         "source": f"PySCF {reference['pyscf_version']} PBE/sf-X2C-1e; {name}; SHA256 {design.digest(reference_path)}",
                                         "forces_Ry_bohr": case["levels"][-1]["forces_Ry_bohr"]},
                           "tolerances": {"force_max_Ry_bohr": tol}})
    fixed = {}
    for symbol, source in (("H", args.h_upf), ("O", args.o_upf)):
        fixed[symbol] = symbol + ".fixed.UPF"
        shutil.copyfile(source, output / fixed[symbol])
    common = {"ecutwfc": 50, "ecutrho": 400, "engine": "oncvpsp", "family": "nc", "profile": "sg15"}
    protocol = {
        "schema_version": 1, "element": "Si", "xc": "pbe", "relativity": "scalar", "repeats": 1,
        "reference_description": "Exploratory molecular all-electron force transferability with fixed H and O pseudopotentials",
        "candidates": [{**common, "id": "sg15-default", "options": {}},
                       {**common, "id": "sg15-radius-103", "options": {"rcut_scale": 1.03}}],
        "benchmarks": benchmarks, "fixed_pseudos": fixed, "selection": "accuracy",
        "convergence": {"base_k_mesh": [1, 1, 1], "tolerance_fraction": .25,
                        "levels": [{"ecutwfc": 65, "ecutrho": 520, "k_mesh": [1, 1, 1]}]},
    }
    design.write_json(output / "protocol.json", protocol)
    design.load_protocol(output / "protocol.json")
    print(output / "protocol.json")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError) as error:
        sys.exit(f"force protocol: {error}")
