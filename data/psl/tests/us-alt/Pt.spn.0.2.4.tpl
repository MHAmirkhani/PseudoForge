 &input
   title='Pt',
   zed=78.,
   rel={{NREL}},
   config='[Xe] 4f14 5d9.0 6s1.0 6p0.0',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Pt.{{FCT}}-spn-rrkjus_psl.0.2.4.UPF',
   nconf=5,
   configts(1)='5s2 5p6 5d9 6s1 6p0'
   configts(2)='5s2 5p6 5d9 6s0 6p0'
   configts(3)='5s2 5p6 5d10 6s0'
   configts(4)='5s2 5p6 5d8 6s1 6p0'
   configts(5)='5s2 5p6 5d8 6s1 6p1'
 /
