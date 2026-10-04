 &input
   title='Ca',
   zed=20.0,
   rel={{NREL}},
   config='[Ar] 3d0.0 4s2.0 4p0',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Ca.{{FCT}}-spn-kjpaw_psl.0.2.3.UPF',
   nconf=5
   configts(1)='3s2 3p6 4s2'
   configts(2)='3s2 3p6 4s1.5 4p0'
   configts(3)='3s2 3p6 4s1 4p0'
   configts(4)='3s2 3p6 4s1 4p1'
   configts(5)='3s2 3p6 4s1 4p0 3d1'
 /
