 &input
   title='Ni',
   zed=28.,
   rel={{NREL}},
   config='[Ar] 4s2 3d8 4p0',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Ni.{{FCT}}-n-rrkjus_psl.0.1.UPF',
   nconf=5
   configts(1)='3d8 4s2'
   configts(2)='3d9 4s1'
   configts(3)='3d8 4s1 4p0'
   configts(4)='3d8 4s1 4p0.5'
   configts(5)='3d7.5 4s2 4p0'
 /
