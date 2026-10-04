 &input
   title='W',
   zed=74.0,
   rel={{NREL}},
   config='[Xe] 4f14 5d4.0 6s2 6p0',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/W.{{FCT}}-spn-kjpaw_psl.0.2.3.UPF',
   nconf=5
   configts(1)='5s2 5p6.0 5d4 6s2'
   configts(2)='5s2 5p6.0 5d4 6s1 6p1'
   configts(3)='5s2 5p6.0 5d4 6s1 6p0'
   configts(4)='5s2 5p6.0 5d3 6s2 6p0'
   configts(5)='5s2 5p6.0 5d3 6s1'
 /
