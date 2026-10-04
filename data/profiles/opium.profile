id=opium
label=OPIUM (Rappe group)
families=nc
provenance=derived
generator=OPIUM
engine=opium
upstream=http://opium.sourceforge.net/
author=Andrew M. Rappe, Karin M. Rabe, Efthimios Kaxiras, J. D. Joannopoulos
reference=https://doi.org/10.1103/PhysRevB.41.1227
license=public domain
summary=Norm-conserving pseudopotentials from OPIUM, the Rappe group's optimised-pseudopotential generator, in ten output formats.
notes=This profile runs OPIUM on a deck PseudoForge builds from the element's ground-state configuration and a cut-off-radius heuristic -- NOT an OPIUM-published reference deck. The physics is verified: Si PBE produces a norm-conserving pseudopotential with transferability 'excellent' by OPIUM's own tc measure (max |dE| = 2e-6 Ry). If you need a reproduction of a specific published OPIUM parameter set, supply it with --params <dir>. By default this profile writes every format OPIUM 4.1.0 can produce for the chosen relativity. Scalar/non-relativistic: UPF, fhi, recpot, siesta, cpmd, casino, champ, qso, ncpp. Fully relativistic: UPF and teter. The other eight writers refuse fully relativistic potentials with their own error message -- that is OPIUM's behaviour, not PseudoForge's; the executor silently drops the formats the chosen mode cannot produce. Six writers also had to be patched: OPIUM 4.1.0 builds the *.pot.ps.l=N scratch filenames from the loop index instead of the real angular momentum, so they crashed on any element with a gap in its l-shells (Fe, Cu, Zn, Au, and every other 3d/5d metal). PseudoForge applies this patch at build time -- see lib/patches/opium/README.md for the details.
available=Every element OPIUM ships a reference deck for. Norm-conserving only. Functional depends on the deck (GGA-PBE or LDA-PZ).
xc_available=pbe pz
rel_available=scalar full
formats=upf fhi recpot siesta cpmd casino champ teter qso ncpp
