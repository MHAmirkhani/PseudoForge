 &input
   title='Cd',
   zed=48.,
   rel={{NREL}},
   config='[Kr] 4d10 5s2.0 5p0',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Cd.{{FCT}}-n-kjpaw_psl.1.0.0.UPF',
   nconf=5
   frozen_core={{FROZEN_CORE}},
   configts(1)='5s2 4d10'
   configts(2)='5s1 5p0 4d10'
   configts(3)='5s2 5p0 4d9'
   configts(4)='5s1 5p0.5 4d10'
   configts(5)='5s2 5p1 4d9'
 /
