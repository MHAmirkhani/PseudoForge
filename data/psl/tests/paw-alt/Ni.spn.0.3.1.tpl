 &input
   title='Ni',
   zed=28.,
   rel={{NREL}},
   config='[Ar] 3d8.0 4s2.0 4p0.0',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Ni.{{FCT}}-spn-kjpaw_psl.0.3.1.UPF',
   nconf=5
   configts(1)='3s2 3p6 3d8 4s2 ',
   configts(2)='3s2 3p6 3d8 4s1 4p0.5',
   configts(3)='3s2 3p6 3d7 4s1 4p0.5',
   configts(4)='3s2 3p6 3d9 4s1 4p0',
   configts(5)='3s2 3p6 3d9 4s0 4p0',
 /
