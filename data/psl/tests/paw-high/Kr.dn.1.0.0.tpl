 &input
   title='Kr',
   zed=36.0,
   rel={{NREL}},
   config='[Ar] 3d10 4s2 4p6.00 4d-2.0',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Kr.{{FCT}}-dn-kjpaw_psl.1.0.0.UPF',
   nconf=5,
   frozen_core={{FROZEN_CORE}},
   configts(1)='4s2 4p6 3d10'
   configts(2)='4s2 4p5 3d10'
   configts(3)='4s1 4p6 3d10'
   configts(4)='4s1 4p5 3d10'
   configts(5)='4s2 4p4 3d10'
 /
