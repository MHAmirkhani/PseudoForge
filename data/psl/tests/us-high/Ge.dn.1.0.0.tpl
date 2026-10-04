 &input
   title='Ge',
   zed=32.,
   rel={{NREL}},
   config='[Ar] 3d10.0 4s2.0 4p2.0 4d-2',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Ge.{{FCT}}-dn-rrkjus_psl.1.0.0.UPF',
   nconf=5
   frozen_core={{FROZEN_CORE}},
   configts(1)='3d10 4s2 4p2'
   configts(2)='3d10 4s2 4p1 4d0'
   configts(3)='3d10 4s2 4p0 4d0'
   configts(4)='3d10 4s1 4p2 4d0'
   configts(5)='3d10 4s1 4p3'
 /
