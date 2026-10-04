 &input
   title='Er',
   zed=68.0,
   rel={{NREL}},
   config='[Xe] 4f12.0 5d0.0 6s2.0 6p0.',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Er.{{FCT}}-spdfn-kjpaw_psl.1.0.0.UPF',
   frozen_core={{FROZEN_CORE}},
   nconf=5,
   configts(1)='4d10 5s2 5p6 6s2 6p0 5d0 4f12 '
   configts(2)='4d10 5s2 5p6 6s1.5 6p0.5 5d0 4f12 '
   configts(3)='4d10 5s2 5p6 6s1 6p0. 5d0 4f12 '
   configts(4)='4d10 5s2 5p6 6s1 6p0. 5d1 4f11.0 '
   configts(5)='4d10 5s2 5p6 6s0 6p0. 5d0 4f13.0 '
 /
