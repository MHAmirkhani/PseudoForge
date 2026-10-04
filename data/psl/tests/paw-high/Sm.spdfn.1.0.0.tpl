 &input
   title='Sm',
   zed=62.0,
   rel={{NREL}},
   config='[Xe] 4f5.5 5d0.5 6s2.0 6p0.0',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Sm.{{FCT}}-spdfn-kjpaw_psl.1.0.0.UPF',
   nconf=5,
   frozen_core={{FROZEN_CORE}},
   configts(1)='4d10 5s2 5p6 6s2 6p0 5d0.5 4f5.5 '
   configts(2)='4d10 5s2 5p6 6s2 6p0 5d0 4f6 '
   configts(3)='4d10 5s2 5p6 6s2 6p0. 5d1 4f5 '
   configts(4)='4d10 5s2 5p6 6s2 6p0. 5d0 4f5.5 '
   configts(5)='4d10 5s2 5p6 6s1 6p1. 5d0 4f5.5 '
 /
