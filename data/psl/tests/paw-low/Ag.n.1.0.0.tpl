 &input
   title='Ag',
   zed=47.,
   rel={{NREL}},
   config='[Kr] 4d9.5 5s1.5 5p0.0',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Ag.{{FCT}}-n-kjpaw_psl.1.0.0.UPF',
   nconf=5
   frozen_core={{FROZEN_CORE}},
   configts(1)='4d9.5 5s1.5 5p0',
   configts(2)='4d10 5s1 ',
   configts(3)='4d9.5 5s0.5 5p1.0',
   configts(4)='4d9 5s2 5p0',
   configts(5)='4d10. 5s0 5p0',
 /
