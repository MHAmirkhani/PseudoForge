 &input
   title='Os',
   zed=76.,
   rel={{NREL}},
   iswitch=2,
   config='[Xe] 4f14.0 5d6.0 6s2.0 6p0.0',
 /
 &test
   file_pseudo='{{PSDIR}}/Os.{{FCT}}-spn-rrkjus_psl.1.0.0.UPF',
   nconf=5
   frozen_core={{FROZEN_CORE}},
   configts(1)='5s2 5p6 5d6 6s2 6p0',
   configts(2)='5s2 5p6 5d6 6s1 6p1',
   configts(3)='5s2 5p6 5d6 6s1 6p0',
   configts(4)='5s2 5p6 5d5 6s2 6p0',
   configts(5)='5s2 5p6 5d7 6s1 6p0',
 /
