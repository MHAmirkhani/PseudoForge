 &input
   title='Cu',
   zed=29.,
   rel={{NREL}},
   config='[Ar] 3d9.5 4s1.5 4p0.0',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Cu.{{FCT}}-spn-rrkjus_psl.1.0.0.UPF',
   nconf=5
   frozen_core={{FROZEN_CORE}},
   configts(1)='3s2 3p6 3d9.5 4s1.5'
   configts(2)='3s2 3p6 3d9.5 4s1 4p0'
   configts(3)='3s2 3p6 3d10 4s1 4p0'
   configts(4)='3s2 3p6 3d10 4s0 4p0'
   configts(5)='3s2 3p6 3d9  4s1 4p0'
 /
