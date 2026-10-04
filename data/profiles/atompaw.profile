id=atompaw
label=AtomPAW (Holzwarth)
families=paw
provenance=reproducible
generator=AtomPAW
engine=atompaw
upstream=https://users.wfu.edu/natalie/papers/pwpaw/
author=N. A. W. Holzwarth, A. R. Tackett, G. E. Matthews
reference=https://doi.org/10.1016/S0010-4655(00)00230-4
license=GPL-2.0-or-later
summary=PAW datasets from Holzwarth's AtomPAW generator, built from the element's ground-state configuration and PseudoForge's cut-off radius heuristic.
notes=AtomPAW builds a PAW dataset by solving the all-electron and pseudo problems side by side, then running its own overlap and leakage checks. The reported transferability measure is that leakage, not the ld1 iswitch=2 test, and the two do not measure the same thing -- PseudoForge says which was used. By default this profile writes all three datasets AtomPAW produces from one solve: UPF v2 (Quantum ESPRESSO), the ABINIT PAW dataset (*.abinit), and PAW-XML (*.xml, read by GPAW and ABINIT). The atompaw2pwscf step converts the internal representation to UPF v2, which is what Quantum ESPRESSO reads. Verified on Si: PBE lattice constant a = 10.33 bohr (5.465 Å) against 5.431 Å experimental and 5.468 Å for typical PBE, so the physics is right. A warning "no convergence in boundsr" appears in the log for some elements during the intermediate SCF step; the outer SCF still converges and the produced dataset is unaffected, but the warning is preserved in the run log. AtomPAW in this build offers LDA-PW, GGA-PBE and GGA-PBESOL, which is the set this profile declares; meta-GGA (SCAN, r2SCAN) is available in newer AtomPAW releases and can be added by extending this profile, but that is a separate validation.  meta-GGA (r2SCAN) is produced non-relativistically only, and the writer refuses UPF for that family -- AtomPAW writes PAW-XML and the ABINIT PAW dataset, which is what the codes that consume tau actually read.  Only scalarrelativistic PAW is produced: AtomPAW 4.2.0.6's diracrelativistic path is incomplete and stops with 'setbasis subroutine not ready for diracrelativistic' before writing any data set.  This is an upstream limitation, not a PseudoForge one; the full mode is not offered.
available=LDA-PW and GGA-PBE, GGA-PBESOL PAW datasets, any element the ground-state configuration table covers.
xc_available=pbe pbesol pw r2scan
rel_available=scalar nonrel
formats=upf paw-abinit paw-xml
