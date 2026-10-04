 &input
   title='Bi',
   zed=83.,
   rel={{NREL}},
   config='[Xe] 4f14.0 5d10.0 6s2.0 6p3.0 6d-2.0',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Bi.{{FCT}}-dn-rrkjus_psl.1.0.0.UPF',
   nconf=5,
   frozen_core={{FROZEN_CORE}},
   configts(1)='5d10 6s2 6p3'
   configts(2)='5d10 6s2 6p2 6d0'
   configts(3)='5d10 6s2 6p1.0 6d0'
   configts(4)='5d10 6s1 6p3.0 6d0'
   configts(5)='5d10 6s1 6p4.0 '
 /
