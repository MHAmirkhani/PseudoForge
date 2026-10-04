 &input
   title='Fe',
   zed=26.,
   rel={{NREL}},
   config='[Ar] 4s2.0 3d6.0 4p0',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Fe.{{FCT}}-n-rrkjus_psl.1.0.0.UPF',
   nconf=5,
   frozen_core={{FROZEN_CORE}},
   configts(1)='4s2 3d6'
   configts(2)='4s1 4p0 3d7'
   configts(3)='4s1 4p1 3d6'
   configts(4)='4s1 4p0 3d6.5'
   configts(5)='4s1 4p0 3d7'
 /
