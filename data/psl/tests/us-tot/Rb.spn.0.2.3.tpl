 &input
   title='Rb',
   zed=37.0,
   rel={{NREL}},
   config='[Kr] 4d-2.0 5s1 5p0',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Rb.{{FCT}}-spn-rrkjus_psl.0.2.3.UPF',
   nconf=5
   configts(1)='4s2 4p6 5s1  '
   configts(2)='4s2 4p6 5s0 5p1 '
   configts(3)='4s2 4p6 5s0 5p0 '
   configts(4)='4s2 4p6 5s0.5  '
   configts(5)='4s2 4p6 5s0.5 5p0 4d0.5'
 /
