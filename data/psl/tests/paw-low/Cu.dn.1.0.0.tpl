 &input
   title='Cu',
   zed=29.,
   rel={{NREL}},
   config='[Ar] 3d9.5 4s1.5 4p0.0',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Cu.{{FCT}}-dn-kjpaw_psl.1.0.0.UPF',
   nconf=5
   frozen_core={{FROZEN_CORE}},
   configts(1)='4s1 3d10'
   configts(2)='4s1.5 4p0 3d9.5'
   configts(3)='4s2 4p0 3d9'
   configts(4)='4s1 4p1 3d9'
   configts(5)='4s0 4p0 3d10'
 /
