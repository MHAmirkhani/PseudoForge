 &input
   title='Ti',
   zed=22.0,
   rel={{NREL}},
   config='[Ar] 3d2.0 4s2 4p0',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Ti.{{FCT}}-spn-rrkjus_psl.1.0.0.UPF',
   nconf=5
   frozen_core={{FROZEN_CORE}},
   configts(1)='3s2 3p6 3d2 4s2'
   configts(2)='3s2 3p6 3d2 4s1 4p1'
   configts(3)='3s2 3p6 3d2 4s0 4p0'
   configts(4)='3s2 3p6 3d1 4s2 4p0'
   configts(5)='3s2 3p6 3d1 4s1'
 /
