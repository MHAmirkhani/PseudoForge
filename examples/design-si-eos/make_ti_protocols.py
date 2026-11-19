#!/usr/bin/env python3
"""Generate a paired Ti metal-to-oxide EOS pilot with fixed oxygen."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil

from make_protocols import ANGSTROM_PER_BOHR, ARMS, RY_EV, SOURCE_SHA256, cubic_qe_input, eos_energy

OXIDE_SHA256 = "6dd6873cde0d80da9126ef9b5bc8f0489ee3e1ad27d2860fab719591579c11f9"
ORIGIN = (0.0, 0.0, 0.0)
FAMILIES = (
    ("bcc", "train", "Ti-X/BCC", -3, 2, (("Ti", ORIGIN),)),
    ("fcc", "train", "Ti-X/FCC", 2, 4, (("Ti", ORIGIN),)),
    ("rocksalt", "test", "Ti-XO", 2, 4, (("Ti", ORIGIN), ("O", (0.5, 0.5, 0.5)))),
    ("fluorite", "test", "Ti-XO2", 2, 4, (
        ("Ti", ORIGIN), ("O", (0.25, 0.25, 0.25)), ("O", (0.75, 0.75, 0.75)),
    )),
)
MASSES = {"Ti": 47.867, "O": 15.999}


def read_reference(path, checksum):
    data = path.read_bytes()
    if hashlib.sha256(data).hexdigest() != checksum:
        raise ValueError(f"{path}: reference SHA-256 differs from the pinned ACWF data")
    return json.loads(data)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("unaries", type=Path)
    parser.add_argument("oxides", type=Path)
    parser.add_argument("oxygen_upf", type=Path, help="same scalar-PBE oxygen UPF for all candidates")
    parser.add_argument("-o", "--output", type=Path, required=True)
    parser.add_argument("--k-mesh", type=int, default=12)
    parser.add_argument("--convergence-mesh", type=int, default=16)
    args = parser.parse_args()
    if not 1 <= args.k_mesh < args.convergence_mesh:
        parser.error("convergence mesh must be larger than the positive base mesh")
    try:
        references = {
            "train": (read_reference(args.unaries, SOURCE_SHA256), SOURCE_SHA256),
            "test": (read_reference(args.oxides, OXIDE_SHA256), OXIDE_SHA256),
        }
    except (ValueError, OSError) as exc:
        parser.error(str(exc))

    args.output.mkdir(parents=True)
    shutil.copyfile(args.oxygen_upf, args.output / "O.fixed.UPF")
    cases = []
    for family, split, key, ibrav, volume_factor, sites in FAMILIES:
        reference, checksum = references[split]
        fit = reference["BM_fit_data"][key]
        if reference["num_atoms_in_sim_cell"][key] != len(sites):
            parser.error(f"{key}: unexpected reference atom count")
        # The two volumes in each pair use one energy gauge. No EOS minimum
        # from a different chemical composition enters the energy differences.
        for tag, factor, other in (("compressed", 0.94, "equilibrium"), ("equilibrium", 1.0, "compressed")):
            case_id = f"{family}-{tag}"
            filename = f"{case_id}.in"
            volume = factor * fit["min_volume"]
            alat = (volume_factor * volume) ** (1 / 3) / ANGSTROM_PER_BOHR
            (args.output / filename).write_text(cubic_qe_input(ibrav, alat, None, sites, "Ti", MASSES))
            energy = eos_energy(volume, fit["min_volume"], fit["bulk_modulus_ev_ang3"], fit["bulk_deriv"])
            cases.append({
                "id": case_id, "split": split, "input": filename, "relative_to": f"{family}-{other}",
                "reference": {"source": f"Bosoni et al., doi:10.1038/s42254-023-00655-3, {key}; SHA-256 {checksum}",
                              "kind": "all-electron", "xc": "pbe", "relativity": "scalar",
                              "energy_Ry": energy / RY_EV},
                "tolerances": {"relative_energy_Ry_atom": 0.005 / RY_EV},
            })

    mesh = [args.k_mesh] * 3
    convergence = {
        "base_k_mesh": mesh, "tolerance_fraction": 0.2,
        "levels": [
            {"ecutwfc": 100, "ecutrho": 640, "k_mesh": mesh},
            {"ecutwfc": 100, "ecutrho": 800, "k_mesh": mesh},
            {"ecutwfc": 100, "ecutrho": 800, "k_mesh": [args.convergence_mesh] * 3},
        ],
    }
    for name, engine, family, profile in ARMS:
        base = {"engine": engine, "family": family, "profile": profile, "ecutwfc": 80, "ecutrho": 640}
        for mode, scales in (("default", (None,)), ("tuned", (0.97, 1.03))):
            protocol = {
                "schema_version": 1, "element": "Ti", "xc": "pbe", "relativity": "scalar",
                "timeout_seconds": 1200, "repeats": 1, "selection": "accuracy", "convergence": convergence,
                "reference_description": "Bosoni et al. all-electron EOS fits; BCC/FCC Ti train, rocksalt TiO and fluorite TiO2 held out. Oxygen is fixed.",
                "fixed_pseudos": {"O": "O.fixed.UPF"}, "benchmarks": cases,
                "candidates": [
                    {**base, "id": "default" if scale is None else f"radius-{scale:.2f}",
                     "options": {} if scale is None else {"rcut_scale": scale}}
                    for scale in scales
                ],
            }
            (args.output / f"{name}-{mode}.json").write_text(json.dumps(protocol, indent=2) + "\n")


if __name__ == "__main__":
    main()
