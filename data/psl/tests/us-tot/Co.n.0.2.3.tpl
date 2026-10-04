 &input
   title='Co',
   zed=27.,
   rel={{NREL}},
   config='[Ar] 4s2 3d7 4p0',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Co.{{FCT}}-n-rrkjus_psl.0.2.3.UPF',
   nconf=5
   configts(1)='3d7 4s2 4p0'
   configts(2)='3d7 4s1 4p0'
   configts(3)='3d7 4s0 4p0'
   configts(4)='3d8 4s1'
   configts(5)='3d8 4s1 4p0'
 /
