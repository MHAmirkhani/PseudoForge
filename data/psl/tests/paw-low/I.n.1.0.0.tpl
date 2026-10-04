 &input
   title='I',
   zed=53.,
   rel={{NREL}},
   config='[Kr] 4d10.0 5s2.0 5p5.0 5d-2.0',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/I.{{FCT}}-n-kjpaw_psl.1.0.0.UPF',
   nconf=5
   frozen_core={{FROZEN_CORE}},
   configts(1)='5s2 5p5'
   configts(2)='5s2 5p4 5d0'
   configts(3)='5s1 5p5 5d1'
   configts(4)='5s2 5p4 5d0.5'
   configts(5)='5s1 5p6'
 /
