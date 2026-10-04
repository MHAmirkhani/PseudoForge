 &input
   title='Mg',
   zed=12.0,
   rel={{NREL}},
   config='[Ne] 3s2.0 3p0 3d-2',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Mg.{{FCT}}-n-kjpaw_psl.0.3.0.UPF',
   nconf=4
   configts(1)='3s2'
   configts(2)='3s1 3p1'
   configts(3)='3s0 3p2'
   configts(4)='3s0 3p1'
 /
