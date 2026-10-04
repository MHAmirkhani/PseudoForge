 &input
   title='Hf',
   zed=72.0,
   rel={{NREL}},
   config='[Xe] 4f14 5d2.0 6s2 6p0',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Hf.{{FCT}}-spdfn-kjpaw_psl.1.0.0.UPF',
   nconf=5
   frozen_core={{FROZEN_CORE}},
   configts(1)='4d10 4f14 5s2 5p6 5d2 6s2'
   configts(2)='4d10 4f14 5s2 5p6 5d2 6s1 6p1'
   configts(3)='4d10 4f14 5s2 5p6 5d2 6s1 6p0'
   configts(4)='4d10 4f14 5s2 5p6 5d2 6s0 6p0'
   configts(5)='4d10 4f14 5s2 5p6 5d1 6s2 6p0'
 /
