 &input
   title='Zr',
   zed=40.0,
   rel={{NREL}},
   config='[Kr] 4d2.0 5s2 5p0',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Zr.{{FCT}}-spn-kjpaw_psl.0.2.3.UPF',
   nconf=5
   configts(1)='4s2 4p6 4d2 5s2'
   configts(2)='4s2 4p6 4d2 5s1 5p1'
   configts(3)='4s2 4p6 4d2 5s1 5p0'
   configts(4)='4s2 4p6 4d1 5s2 5p0'
   configts(5)='4s2 4p6 4d3 5s1'
 /
