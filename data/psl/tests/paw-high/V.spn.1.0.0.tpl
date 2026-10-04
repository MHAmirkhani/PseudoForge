 &input
   title='V',
   zed=23.0,
   rel={{NREL}},
   config='[Ar] 3d3.0 4s2 4p0',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/V.{{FCT}}-spn-kjpaw_psl.1.0.0.UPF',
   nconf=5
   frozen_core={{FROZEN_CORE}},
   configts(1)='3s2 3p6 3d3 4s2'
   configts(2)='3s2 3p6 3d3 4s1 4p1'
   configts(3)='3s2 3p6 3d3 4s1'
   configts(4)='3s2 3p6 3d2 4s2 4p0'
   configts(5)='3s2 3p6 3d4 4s1' 
 /
