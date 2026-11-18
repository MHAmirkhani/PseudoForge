#!/usr/bin/env python3
"""Prepare matched Si EOS pairs for the existing PseudoForge design runner."""
import argparse
import hashlib
import json
import math
from pathlib import Path

SOURCE_SHA256 = "d7844caa127eae860fe5087ead42f80d1b6b5eb952a686ff4b912ddaed7db48b"
RY_EV = 13.605693122994
ANGSTROM_PER_BOHR = 0.529177210903
ARMS = (
    ("oncv-nc", "oncvpsp", "nc", "sg15"),
    ("ld1-us", "ld1", "us", "psl-high"),
    ("atompaw-paw", "atompaw", "paw", "atompaw"),
)


def eos_energy(volume, equilibrium_volume, bulk_modulus, bulk_derivative):
    """Third-order Birch–Murnaghan energy relative to the minimum, in eV/cell."""
    eta = (equilibrium_volume / volume) ** (2 / 3)
    strain = eta - 1
    return 9 * equilibrium_volume * bulk_modulus / 16 * (
        bulk_derivative * strain**3 + (6 - 4 * eta) * strain**2
    )


def qe_input(volume, mesh):
    # ibrav=2 uses the FCC primitive cell with one fourth of the cubic volume.
    alat = (4 * volume) ** (1 / 3) / ANGSTROM_PER_BOHR
    mesh_row = "{{K_MESH}}" if mesh is None else f"{mesh} {mesh} {mesh}"
    return f"""&CONTROL
 calculation='scf', prefix='{{{{PREFIX}}}}', outdir='{{{{OUTDIR}}}}',
 pseudo_dir='{{{{PSEUDO_DIR}}}}', disk_io='none'
/
&SYSTEM
 ibrav=2, celldm(1)={alat:.12f}, nat=2, ntyp=1,
 ecutwfc={{{{ECUTWFC}}}}, ecutrho={{{{ECUTRHO}}}},
 occupations='smearing', smearing='fd', degauss=0.0045
/
&ELECTRONS
 conv_thr=1.0d-10, mixing_beta=0.3
/
ATOMIC_SPECIES
 Si 28.0855 {{{{UPF}}}}
ATOMIC_POSITIONS alat
 Si 0.0 0.0 0.0
 Si 0.25 0.25 0.25
K_POINTS automatic
 {mesh_row} 0 0 0
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reference", type=Path, help="pinned ACWF unary all-electron EOS JSON")
    parser.add_argument("-o", "--output", required=True, type=Path, help="new output directory")
    parser.add_argument("--k-mesh", type=int, help="override the reference-spacing mesh for a smoke run")
    parser.add_argument("--convergence-mesh", type=int,
                        help="check wavefunction and density cutoff increases, then this denser mesh")
    args = parser.parse_args()
    if args.k_mesh is not None and args.k_mesh < 1:
        parser.error("--k-mesh must be positive")
    if args.convergence_mesh is not None and (
            args.k_mesh is None or args.convergence_mesh <= args.k_mesh):
        parser.error("--convergence-mesh requires a smaller --k-mesh")
    data = args.reference.read_bytes()
    if hashlib.sha256(data).hexdigest() != SOURCE_SHA256:
        parser.error("reference SHA-256 differs from the pinned ACWF data")
    reference = json.loads(data)
    key = "Si-X/Diamond"
    fit = reference["BM_fit_data"][key]
    if reference["num_atoms_in_sim_cell"][key] != 2:
        parser.error("Si diamond reference must use a two-atom primitive cell")
    args.output.mkdir(parents=True)
    (args.output / "reference-source.json").write_bytes(data)
    cases = []
    for split, factors in (("train", (0.96, 1.02)), ("test", (0.98, 1.04))):
        for index, factor in enumerate(factors):
            case_id = f"{split}-{index + 1}"
            volume = factor * fit["min_volume"]
            alat_angstrom = (4 * volume) ** (1 / 3)
            reciprocal_length = 2 * math.pi * math.sqrt(3) / alat_angstrom
            mesh = args.k_mesh or math.ceil(reciprocal_length / 0.06)
            filename = f"{case_id}.in"
            (args.output / filename).write_text(qe_input(volume, None if args.convergence_mesh else mesh))
            energy = eos_energy(volume, fit["min_volume"], fit["bulk_modulus_ev_ang3"], fit["bulk_deriv"])
            cases.append({
                "id": case_id, "split": split, "input": filename,
                "relative_to": f"{split}-{2 - index}",
                "reference": {
                    "source": f"Bosoni et al., doi:10.1038/s42254-023-00655-3, Si-X/Diamond average EOS, fraction {factor}; SHA-256 {SOURCE_SHA256}",
                    "kind": "all-electron", "xc": "pbe", "relativity": "scalar", "energy_Ry": energy / RY_EV,
                },
                "tolerances": {"relative_energy_Ry_atom": 0.002 / RY_EV},
            })
    for name, engine, family, profile in ARMS:
        base = {"engine": engine, "family": family, "profile": profile, "ecutwfc": 60, "ecutrho": 480}
        for mode, scales in (("default", (None,)), ("tuned", (0.97, 1.03))):
            protocol = {
                "schema_version": 1, "element": "Si", "xc": "pbe", "relativity": "scalar",
                "timeout_seconds": 600, "repeats": 1,
                "reference_description": "Exploratory elemental Si diamond EOS; FLEUR/WIEN2k average fit from Bosoni et al. The two splits are volumes in the same structural family.",
                "benchmarks": cases,
                "candidates": [
                    {**base, "id": "default" if scale is None else f"radius-{scale:.2f}",
                     "options": {} if scale is None else {"rcut_scale": scale}}
                    for scale in scales
                ],
            }
            if args.convergence_mesh:
                base_mesh = [args.k_mesh] * 3
                protocol["selection"] = "accuracy"
                protocol["convergence"] = {
                    "base_k_mesh": base_mesh,
                    "tolerance_fraction": 0.1,
                    "levels": [
                        {"ecutwfc": 80, "ecutrho": 480, "k_mesh": base_mesh},
                        {"ecutwfc": 80, "ecutrho": 640, "k_mesh": base_mesh},
                        {"ecutwfc": 80, "ecutrho": 640, "k_mesh": [args.convergence_mesh] * 3},
                    ],
                }
            (args.output / f"{name}-{mode}.json").write_text(json.dumps(protocol, indent=2) + "\n")


if __name__ == "__main__":
    main()
