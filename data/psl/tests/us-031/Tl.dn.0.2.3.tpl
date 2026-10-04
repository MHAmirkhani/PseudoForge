 &input
   title='Tl',
   zed=81.,
   rel={{NREL}},
   config='[Xe] 4f14.0 5d10.0 6s2.0 6p1.0 6d-1',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Tl.{{FCT}}-dn-rrkjus_psl.0.2.3.UPF',
   nconf=5,
   configts(1)='5d10 6s2 6p1'
   configts(2)='5d10 6s2 6p0 6d0'
   configts(3)='5d10 6s1 6p1'
   configts(4)='5d10 6s1 6p2'
   configts(5)='5d10 6s1 6p0'
 /
