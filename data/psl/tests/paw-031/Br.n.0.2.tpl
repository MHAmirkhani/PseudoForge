 &input
   title='Br',
   zed=35.,
   rel={{NREL}},
   config='[Ar] 3d10.0 4s2.0 4p5.0 4d-2.0',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Br.{{FCT}}-n-kjpaw_psl.0.2.UPF',
   nconf=5,
   configts(1)='4s2 4p5'
   configts(2)='4s2 4p4 4d0'
   configts(3)='4s1 4p5 4d0'
   configts(4)='4s1 4p4'
   configts(5)='4s1 4p6'
 /
