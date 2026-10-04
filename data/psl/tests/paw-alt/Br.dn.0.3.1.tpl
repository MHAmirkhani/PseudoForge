 &input
   title='Br',
   zed=35.,
   rel={{NREL}},
   config='[Ar] 3d10.0 4s2.0 4p5.0 4d-1',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Br.{{FCT}}-dn-kjpaw_psl.0.3.1.UPF',
   nconf=5
   configts(1)='3d10 4s2 4p5 ',
   configts(2)='3d10 4s2 4p4 4d0',
   configts(3)='3d10 4s2 4p3 4d0.5',
   configts(4)='3d10 4s1 4p5 4d0',
   configts(5)='3d10 4s1 4p4 4d0',
 /
