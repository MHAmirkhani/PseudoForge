 &input
   title='Al',
   zed=13.0,
   rel={{NREL}},
   config='[Ne] 3s2 3p1 3d-2.0 4f-2.0',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Al.{{FCT}}-n-rrkjus_psl.0.2.2.UPF',
   nconf=5
   configts(1)='3s2 3p1'
   configts(2)='3s2 3p0 3d0'
   configts(3)='3s1.5 3p0 3d0.5'
   configts(4)='3s1 3p2 '
   configts(5)='3s1 3p1 3d0'
 /
