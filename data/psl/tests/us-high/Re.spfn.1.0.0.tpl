 &input
   title='Re',
   zed=75.0,
   rel={{NREL}},
   config='[Xe] 4f14 5d5.0 6s2 6p0',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Re.{{FCT}}-spfn-rrkjus_psl.1.0.0.UPF',
   nconf=5
   frozen_core={{FROZEN_CORE}},
   configts(1)='4f14 5s2 5p6 5d5 6s2'
   configts(2)='4f14 5s2 5p6 5d5 6s1.5 6p0'
   configts(3)='4f14 5s2 5p6 5d5 6s1 6p1'
   configts(4)='4f14 5s2 5p6 5d4 6s2'
   configts(5)='4f14 5s2 5p6 5d6 6s1'
 /
