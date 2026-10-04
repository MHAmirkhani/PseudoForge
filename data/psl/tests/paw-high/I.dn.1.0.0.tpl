 &input
   title='I',
   zed=53.,
   rel={{NREL}},
   config='[Kr] 4d10.0 5s2.0 5p5.0 5d-2.0',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/I.{{FCT}}-dn-kjpaw_psl.1.0.0.UPF',
   nconf=5
   frozen_core={{FROZEN_CORE}},
   configts(1)='4d10 5s2 5p5'
   configts(2)='4d10 5s2 5p4 5d0'
   configts(3)='4d10 5s2 5p3 5d0'
   configts(4)='4d10 5s2 5p2 5d0'
   configts(5)='4d10 5s1 5p4'
 /
