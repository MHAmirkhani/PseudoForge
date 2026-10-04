 &input
   title='Pb',
   zed=82.0,
   rel={{NREL}},
   config='[Xe] 4f14 5d10 6s2 6p2 6d-1',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Pb.{{FCT}}-dn-rrkjus_psl.0.2.2.UPF',
   nconf=5
   configts(1)='5d10. 6s2 6p2'
   configts(2)='5d10. 6s2 6p1 6d0'
   configts(3)='5d10. 6s2 6p0 6d0'
   configts(4)='5d10. 6s1 6p3'
   configts(5)='5d10. 6s1 6p2 6d0'
 /
