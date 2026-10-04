id=cp2k-gth
label=GTH (Goedecker-Teter-Hutter, CP2K)
families=nc
provenance=library
generator=gth
engine=gth
upstream=https://www.cp2k.org/static/potentials
author=Goedecker, Teter, Hutter; Hartwigsen, Goedecker, Hutter; maintained by M. Krack
reference=https://www.cp2k.org/static/potentials
license=see the CP2K distribution
summary=The analytic GTH and HGH coefficient tables, covering essentially the whole periodic table in a compact closed form.
notes=PseudoForge ships both halves of this library: the published coefficient tables (1743 entries across eight functionals, plus the spin-orbit set) and the 435 published generation input sets, so it works offline either way. Two modes. By default the published coefficients are written out in the layout you ask for, which is an exact format conversion of CP2K's own numbers. With --refit, atom.x re-solves the all-electron atom and pseudo.x re-runs the simplex fit from the published starting point; the result lands near the published one but is not identical, and is labelled PSEUDOFORGE. An earlier version of this file said GTH could not be generated because it is analytic. That was wrong: analytic describes the form of the answer, not the absence of a generator, and CP2K publishes the generator. What remains true is that Quantum ESPRESSO cannot read these -- its upfconv.x lists .gth as "DOES NOT WORK" -- so there is no UPF here. CP2K, CPMD, ABINIT and BigDFT read them directly.
available=BLYP, BP, HCTH120, HCTH407, OLYP, PADE (LDA), PBE and PBEsol. Bundled: 1743 coefficient entries and 435 generation input sets.
xc_available=pz pbe pbesol blyp bp olyp hcth120 hcth407
# rel_available: GTH coefficients carry no relativistic variant here; the full-relativistic runs copied the same tables.
rel_available=scalar
families_note=NC analytic; whole periodic table
formats=gth gth-cpmd gth-abinit
