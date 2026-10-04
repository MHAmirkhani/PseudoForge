 &input
   title='Ni',
   zed=28.,
   rel={{NREL}},
   config='[Ar] 4s2 3d8 4p0',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Ni.{{FCT}}-spn-rrkjus_psl.1.0.0.UPF',
   nconf=5
   frozen_core={{FROZEN_CORE}},
   configts(1)='3s2 3p6 3d8 4s2'
   configts(2)='3s2 3p6 3d8 4s1 4p0'
   configts(3)='3s2 3p6 3d8 4s1 4p0.5'
   configts(4)='3s2 3p6 3d9 4s1'
   configts(5)='3s2 3p6 3d7.5 4s2 4p0'
 /
