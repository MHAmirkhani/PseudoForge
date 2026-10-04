id=scan-tm
label=SCAN norm-conserving (Yao and Kanai)
families=nc
provenance=external
generator=unverified
engine=oncvpsp
upstream=https://yaoyi92.github.io/scan-tm-pseudopotentials.html
author=Y. Yao and Y. Kanai
reference=https://yaoyi92.github.io/scan-tm-pseudopotentials.html
license=see the distribution
summary=Norm-conserving pseudopotentials generated with the SCAN meta-GGA itself, rather than with a semilocal parent.
notes=Tested directly rather than assumed. PseudoForge builds ONCVPSP against libxc 7.1.2, and libxc does provide SCAN (XC_MGGA_X_SCAN=263, XC_MGGA_C_SCAN=267) and r2SCAN. ONCVPSP still refuses them: src/functionals.F90 reaches XC_FAMILY_MGGA and stops with 'meta GGA not coded yet'. Running it with iexc=-263267 exits without writing a pseudopotential. So the earlier expectation that a libxc build would unlock SCAN was wrong -- the gap is an unimplemented branch in ONCVPSP, not a missing library, and no engine PseudoForge drives has a meta-GGA path. What libxc did unlock is the GGA range: PBEsol, BLYP, revPBE, WC, PW91 and AM05. Until an engine implements meta-GGA this profile stays import-only. In practice SCAN calculations are routinely run with PBE-generated pseudopotentials, which is what --xc scan does here, with a warning.
available=SCAN, norm-conserving, for a selected set of elements.
xc_available=scan
rel_available=scalar
families_note=NC, generated against SCAN itself
formats=upf psp8 xml
