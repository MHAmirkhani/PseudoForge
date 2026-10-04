 &input
   title='Cd',
   zed=48.,
   rel={{NREL}},
   config='[Kr] 4d9.5 5s2.0 5p0.5',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Cd.{{FCT}}-spn-kjpaw_psl.1.0.0.UPF',
   nconf=5
   frozen_core={{FROZEN_CORE}},
   configts(1)='4s2 4p6 4d9.5 5s2 5p0.5 ',
   configts(2)='4s2 4p6 4d9.5 5s2 5p0',
   configts(3)='4s2 4p6 4d10  5s2 5p0',
   configts(4)='4s2 4p6 4d10  5s1 5p0',
   configts(5)='4s2 4p6 4d9   5s2 5p0',
 /
