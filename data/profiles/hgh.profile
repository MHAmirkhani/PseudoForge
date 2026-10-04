id=hgh
label=HGH (Hartwigsen-Goedecker-Hutter)
families=nc
provenance=library
generator=gth
upstream=HGH / GTH parameter tables
author=C. Hartwigsen, S. Goedecker, J. Hutter
reference=https://doi.org/10.1103/PhysRevB.58.3641
license=public parameter tables
summary=Fully analytic separable norm-conserving pseudopotentials defined by a small table of coefficients rather than by a radial grid.
notes=HGH is the relativistic extension of GTH to the whole periodic table, so it shares this tool's GTH engine and data. This file used to say there was no generator and no input deck, and called that a real exception rather than a gap. That was simply wrong -- CP2K publishes both the fitting code and the per-element inputs, and PseudoForge now drives them. The coefficients ship here and are written out exactly; --refit re-runs the fit instead.
engine=gth
available=LDA and the GGA sets, essentially the whole periodic table.
xc_available=pz pbe pbesol blyp bp olyp hcth120 hcth407
# rel_available: The HGH tables used here carry no spin-orbit terms; the full-relativistic runs copied the same tables.
rel_available=scalar
families_note=NC analytic coefficients, H to Rn
formats=gth gth-cpmd gth-abinit
