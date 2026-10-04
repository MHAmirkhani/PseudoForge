 &input
   title='Kr',
   zed=36.0,
   rel={{NREL}},
   config='[Ar] 3d10 4s2 4p6.00 4d-2.0',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Kr.{{FCT}}-n-kjpaw_psl.0.2.3.UPF',
   nconf=5
   configts(1)='4s2 4p6'
   configts(2)='4s2 4p5 4d0'
   configts(3)='4s2 4p5 4d1'
   configts(4)='4s1 4p6 4d0'
   configts(5)='4s1 4p5 4d1'
 /
