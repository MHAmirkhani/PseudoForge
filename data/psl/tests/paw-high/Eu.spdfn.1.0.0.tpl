 &input
   title='Eu',
   zed=63.0,
   rel={{NREL}},
   config='[Xe] 4f7.0 5d0.0 6s2. 6p0.',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Eu.{{FCT}}-spdfn-kjpaw_psl.1.0.0.UPF',
   nconf=5,
   frozen_core={{FROZEN_CORE}},
   configts(1)='4d10 5s2 5p6 6s2 6p0 5d0 4f7 '
   configts(2)='4d10 5s2 5p6 6s1.5 6p0.5 5d0 4f7 '
   configts(3)='4d10 5s2 5p6 6s2 6p0. 5d1 4f6 '
   configts(4)='4d10 5s2 5p6 6s2 6p0. 5d0 4f6 '
   configts(5)='4d10 5s2 5p6 6s1 6p0. 5d0 4f7.5 '
 /
