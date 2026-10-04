id=fhi
label=FHI (fhi98PP)
families=nc
provenance=reproducible
generator=fhi98PP
upstream=Fritz-Haber-Institut pseudopotential tables
author=M. Fuchs, M. Scheffler
reference=https://doi.org/10.1016/S0010-4655(98)00201-X
license=see FHI distribution
summary=Norm-conserving pseudopotentials in the legacy .cpi/.fhi format, widely used by ABINIT and older QE work.
notes=Hamann and Troullier-Martins norm-conserving schemes. The per-element database ships inside the fhi98PP distribution PseudoForge builds (bin/Elements/{Ham,TM}), so it generates without any download. Caveat: Quantum ESPRESSO 7.x dropped .cpi/.fhi from its format dispatch, so the result stays in .cpi -- readable by ABINIT, not by QE. See docs/ENGINES.md.
engine=fhi98pp
available=LDA and PBE norm-conserving, Hamann and Troullier-Martins schemes, from the fhi98PP element database.
# xc_available: Every fhi deck sets iexc 8, which fhi98PP's own table defines as LDA, Ceperley-Alder parametrised by Perdew-Wang (1991). This profile declared pz and pbe; both ran iexc 8, so both produced PW-LDA under other names.
xc_available=pw
rel_available=scalar
families_note=NC, Hamann and Troullier-Martins
formats=cpi
