 &input
   title='Si',
   zed=14.0,
   rel={{NREL}},
   config='[Ne] 3s2 3p2 3d-2.0',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Si.{{FCT}}-n-kjpaw_psl.0.1.UPF',
   nconf=5,
   configts(1)='3s2 3p2'
   configts(2)='3s2 3p1 3d0'
   configts(3)='3s2 3p0 3d0'
   configts(4)='3s1 3p3'
   configts(5)='3s1 3p2 3d0'
 /
