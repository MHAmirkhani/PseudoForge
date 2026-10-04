 &input
   title='Mo',
   zed=42.0,
   rel={{NREL}},
   config='[Kr] 4d5.0 5s1 5p0',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Mo.{{FCT}}-spn-kjpaw_psl.0.3.0.UPF',
   nconf=5
   configts(1)='4s2 4p6 4d5 5s1'
   configts(2)='4s2 4p6 4d5 5s0 5p0'
   configts(3)='4s2 4p6 4d6 5s0'
   configts(4)='4s2 4p6 4d4 5s2' 
   configts(5)='4s2 4p6 4d4 5s1 5p0'
 /
