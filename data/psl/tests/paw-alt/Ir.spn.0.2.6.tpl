 &input
   title='Ir',
   zed=77.,
   rel={{NREL}},
   config='[Xe] 4f14.0 5d7.0 6s2.0 6p0.0',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Ir.{{FCT}}-spn-kjpaw_psl.0.2.6.UPF',
   nconf=5
   configts(1)='5s2 5p6 5d7 6s2',
   configts(2)='5s2 5p6 5d7 6s1 6p0',
   configts(3)='5s2 5p6 5d7 6s0 6p1',
   configts(4)='5s2 5p6 5d6 6s2 6p0',
   configts(5)='5s2 5p6 5d6 6s2 6p1',
 /
