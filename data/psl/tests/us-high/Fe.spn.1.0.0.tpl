 &input
   title='Fe',
   zed=26.,
   rel={{NREL}},
   config='[Ar] 4s2.0 3d6.0 4p0',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Fe.{{FCT}}-spn-rrkjus_psl.1.0.0.UPF',
   nconf=5
   frozen_core={{FROZEN_CORE}},
   configts(1)='3s2 3p6 3d6 4s2'
   configts(2)='3s2 3p6 3d6 4s1 4p0'
   configts(3)='3s2 3p6 3d6 4s1 4p1'
   configts(4)='3s2 3p6 3d7 4s1'
   configts(5)='3s2 3p6 3d7 4s0 4p1'
 /
