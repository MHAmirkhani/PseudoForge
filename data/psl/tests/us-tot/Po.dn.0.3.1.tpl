 &input
   title='Po',
   zed=84.,
   rel={{NREL}},
   config='[Xe] 4f14.0 5d10.0 6s2.0 6p4.0 6d-2',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Po.{{FCT}}-dn-rrkjus_psl.0.3.1.UPF',
   nconf=5,
   configts(1)='5d10 6s2 6p4',
   configts(3)='5d10 6s2 6p3',
   configts(2)='5d10 6s2 6p2 6d0.5',
   configts(4)='5d10 6s1 6p4',
   configts(5)='5d10 6s1 6p5',
 /
