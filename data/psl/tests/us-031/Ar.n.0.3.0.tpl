 &input
   title='Ar',
   zed=18.0,
   rel={{NREL}},
   config='[Ar] 3d-2',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Ar.{{FCT}}-n-rrkjus_psl.0.3.0.UPF',
   nconf=5
   configts(1)='3s2 3p6'
   configts(2)='3s2 3p5 3d0'
   configts(3)='3s2 3p4 3d1'
   configts(4)='3s1 3p6 3d0'
   configts(5)='3s1 3p5 3d0.5'
 /
