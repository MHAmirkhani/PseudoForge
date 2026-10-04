 &input
   title='Rn',
   zed=86.,
   rel={{NREL}},
   config='[Xe] 4f14.0 5d10.0 6s2.0 6p6.0 6d-2.0',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Rn.{{FCT}}-dn-rrkjus_psl.1.0.0.UPF',
   nconf=5
   frozen_core={{FROZEN_CORE}},
   configts(1)='5d10 6s2 6p6'
   configts(2)='5d10 6s2 6p5'
   configts(3)='5d10 6s2 6p4'
   configts(4)='5d10 6s1 6p6'
   configts(5)='5d10 6s1 6p5'
 /
