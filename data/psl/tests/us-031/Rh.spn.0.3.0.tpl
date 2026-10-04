 &input
   title='Rh',
   zed=45.,
   rel={{NREL}},
   config='[Kr] 4d8. 5s1.0 5p0.0',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Rh.{{FCT}}-spn-rrkjus_psl.0.3.0.UPF',
   nconf=5
   configts(1)='4s2 4p6 4d8 5s1',
   configts(2)='4s2 4p6 4d8 5s0 5p0',
   configts(3)='4s2 4p6 4d7 5s2 5p0',
   configts(4)='4s2 4p6 4d7 5s1 5p1',
   configts(5)='4s2 4p6 4d7 5s0 5p0',
 /
