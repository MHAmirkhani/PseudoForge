 &input
   title='Ce',
   zed=58.0,
   rel={{NREL}},
   config='[Xe] 4f1 5d1.0 6s2. 6p0.',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Ce.{{FCT}}-spdfn-rrkjus_psl.1.0.0.UPF',
   nconf=5,
   frozen_core={{FROZEN_CORE}},
   configts(1)='4d10. 5s2 5p6 6s2 6p0 5d1 4f1 '
   configts(2)='4d10. 5s2 5p6 6s2 6p1 5d0 4f1 '
   configts(3)='4d10. 5s2 5p6 6s1 6p0 5d1 4f0.5 '
   configts(4)='4d10. 5s2 5p6 6s1 6p0 5d1 4f0.5 '
   configts(5)='4d10. 5s2 5p6 6s1 6p1 5d1 4f0.5'
 /
