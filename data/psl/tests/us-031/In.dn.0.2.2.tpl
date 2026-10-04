 &input
   title='In',
   zed=49.,
   rel={{NREL}},
   config='[Kr] 4d10.0 5s2.0 5p1.0 5d0',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/In.{{FCT}}-dn-rrkjus_psl.0.2.2.UPF',
   nconf=5
   configts(1)='4d10 5s2 5p1'
   configts(2)='4d10 5s2 5p0 5d0'
   configts(3)='4d10 5s2 5p0 5d0'
   configts(4)='4d10 5s1 5p2'
   configts(5)='4d10 5s1 5p1 5d0'
 /
