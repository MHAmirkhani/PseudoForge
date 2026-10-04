 &input
   title='Ta',
   zed=73.0,
   rel={{NREL}},
   config='[Xe] 4f14 5d3.0 6s2 6p0',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Ta.{{FCT}}-spn-kjpaw_psl.0.2.UPF',
   nconf=5,
   configts(1)='5s2 5p6 5d3 6s2 6p0'
   configts(2)='5s2 5p6 5d3 6s1 6p1'
   configts(3)='5s2 5p6 5d3 6s1 6p0'
   configts(4)='5s2 5p6 5d2 6s2 6p0'
   configts(5)='5s2 5p6 5d2 6s1 6p1'
 /
