 &input
   title='Sn',
   zed=50.,
   rel={{NREL}},
   config='[Kr] 4d10.0 5s2.0 5p2.0 5d-1',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Sn.{{FCT}}-dn-kjpaw_psl.1.0.0.UPF',
   nconf=5,
   frozen_core={{FROZEN_CORE}},
   configts(1)='4d10 5s2 5p2'
   configts(2)='4d10 5s2 5p1 5d0'
   configts(3)='4d10 5s2 5p0'
   configts(4)='4d10 5s1 5p3'
   configts(5)='4d10 5s1 5p2 5d0'
 /
