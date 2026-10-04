 &input
   title='Ir',
   zed=77.,
   rel={{NREL}},
   config='[Xe] 4f14.0 5d7.0 6s2.0 6p0.0',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Ir.{{FCT}}-spfn-rrkjus_psl.1.0.0.UPF',
   nconf=5,
   frozen_core={{FROZEN_CORE}},
   configts(1)='4f14 5s2 5p6 6s2 6p0 5d7'
   configts(2)='4f14 5s2 5p6 6s1.5 6p0 5d7'
   configts(3)='4f14 5s2 5p6 6s1.5 6p0.3 5d7'
   configts(4)='4f14 5s2 5p6 6s2 6p0.0 5d6'
   configts(5)='4f14 5s2 5p6 6s2 6p1.0 5d6'
 /
