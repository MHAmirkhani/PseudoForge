 &input
   title='K',
   zed=19.0,
   rel={{NREL}},
   config='[Ar] 3d-2 4s1 4p0',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/K.{{FCT}}-spn-kjpaw_psl.1.0.0.UPF',
   nconf=5
   frozen_core={{FROZEN_CORE}},
   configts(1)='3s2 3p6 4s1'
   configts(2)='3s2 3p6 4s0.5 4p0.5'
   configts(3)='3s2 3p6 4s0.5 3d0'
   configts(4)='3s2 3p6 4s0.5 4p0 '
   configts(5)='3s2 3p6 4s0.75 4p0 3d0.25'
 /
