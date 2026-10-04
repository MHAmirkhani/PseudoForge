 &input
   title='Hg',
   zed=80.0,
   rel={{NREL}},
   config='[Xe] 4f14. 5d10 6s2 6p-1',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Hg.{{FCT}}-spn-rrkjus_psl.1.0.0.UPF',
   nconf=5,
   frozen_core={{FROZEN_CORE}},
   configts(1)='5s2 5p6 5d10 6s2'
   configts(2)='5s2 5p6 5d10 6s1 6p0'
   configts(3)='5s2 5p6 5d10 6s0 6p1'
   configts(4)='5s2 5p6 5d9  6s2 6p0'
   configts(5)='5s2 5p6 5d9  6s1 6p0'
 /
