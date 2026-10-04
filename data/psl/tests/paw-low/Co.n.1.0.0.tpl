 &input
   title='Co',
   zed=27.,
   rel={{NREL}},
   config='[Ar] 4s2 3d7 4p0',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Co.{{FCT}}-n-kjpaw_psl.1.0.0.UPF',
   nconf=5
   frozen_core={{FROZEN_CORE}},
   configts(1)='3d7 4s2 4p0'
   configts(2)='3d7 4s1 4p0'
   configts(3)='3d7 4s0 4p0'
   configts(4)='3d8 4s1'
   configts(5)='3d8 4s0 4p0'
 /
