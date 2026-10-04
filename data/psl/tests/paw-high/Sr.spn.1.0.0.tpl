 &input
   title='Sr',
   zed=38.0,
   rel={{NREL}},
   config='[Kr] 4d0.0 5s2 5p0',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Sr.{{FCT}}-spn-kjpaw_psl.1.0.0.UPF',
   nconf=5
   frozen_core={{FROZEN_CORE}},
   configts(1)='4s2 4p6 5s2'
   configts(2)='4s2 4p6 5s1.5'
   configts(3)='4s2 4p6 5s1 5p1'
   configts(4)='4s2 4p6 5s1 5p0'
   configts(5)='4s2 4p6 5s1.75 5p0 4d0.25'
 /
