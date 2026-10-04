 &input
   title='Ce',
   zed=58.0,
   rel={{NREL}},
   config='[Xe] 4f1 5d1.0 6s1.5 6p0.5',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Ce.{{FCT}}-spdn-rrkjus_psl.1.0.0.UPF',
   nconf=5,
   configts(1)='5s2 5p6 6s1.5 6p0.5  5d1  '
   configts(2)='5s2 5p6 6s2   6p0    5d1 '
   configts(3)='5s2 5p6 6s2   6p1.   5d0  '
   configts(4)='5s2 5p6 6s2   6p0.   5d0  '
   configts(5)='5s2 5p6 6s1   6p0.   5d1  '
 /
