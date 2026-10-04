 &input
   title='Ag',
   zed=47.,
   rel={{NREL}},
   config='[Kr] 4d10.0 5s1.0 5p0.0',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Ag.{{FCT}}-spn-rrkjus_psl.0.3.1.UPF',
   nconf=5
   configts(1)='4s2 4p6 4d10 5s1 ',
   configts(2)='4s2 4p6 4d9 5s1 5p0.5',
   configts(3)='4s2 4p6 4d8.5 5s1 5p0.5',
   configts(4)='4s2 4p6 4d9 5s2 5p0',
   configts(5)='4s2 4p6 4d10. 5s0 5p0',
 /
