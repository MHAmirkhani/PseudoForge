 &input
   title='S',
   zed=16,
   rel={{NREL}},
   config='[Ne] 3s2 3p4 3d-2',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/S.{{FCT}}-n-kjpaw_psl.0.1.UPF',
   nconf=5,
   configts(1)='3s2 3p4'
   configts(2)='3s2 3p3 3d0'
   configts(3)='3s2 3p2'
   configts(4)='3s1 3p4 3d0'
   configts(5)='3s1 3p5'
 /
