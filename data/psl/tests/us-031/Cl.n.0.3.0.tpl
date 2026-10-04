 &input
   title='Cl',
   zed=17,
   rel={{NREL}},
   config='[Ne] 3s2 3p5 3d-2',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Cl.{{FCT}}-n-rrkjus_psl.0.3.0.UPF',
   nconf=5
   configts(1)='3s2 3p5'
   configts(2)='3s2 3p4 3d0'
   configts(3)='3s2 3p3 3d0'
   configts(4)='3s1 3p5 3d0'
   configts(5)='3s1 3p6'
 /
