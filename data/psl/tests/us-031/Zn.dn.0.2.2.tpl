 &input
   title='Zn',
   zed=30.,
   rel={{NREL}},
   config='[Ar] 3d10. 4s2. 4p0.0',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Zn.{{FCT}}-dn-rrkjus_psl.0.2.2.UPF',
   nconf=5,
   configts(1)='3d10 4s2'
   configts(2)='3d10 4s1 4p0'
   configts(3)='3d10 4s0 4p1 '
   configts(4)='3d9.5 4s2. 4p0'
   configts(5)='3d9 4s2. 4p0'
 /
