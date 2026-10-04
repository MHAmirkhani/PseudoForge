 &input
   title='Sm',
   zed=62.0,
   rel={{NREL}},
   config='[Xe] 4f5.0 5d1.0 6s1.5 6p0.5',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Sm.{{FCT}}-spdn-rrkjus_psl.1.0.0.UPF',
   nconf=5,
   configts(1)='5s2 5p6 6s1.5 6p0.5 5d1'
   configts(2)='5s2 5p6 6s2 6p0 5d1'
   configts(3)='5s2 5p6 6s1 6p0. 5d1'
   configts(4)='5s2 5p6 6s1 6p1. 5d1'
   configts(5)='5s2 5p6 6s0 6p1. 5d1'
 /
