 &input
   title='Nb',
   zed=41.0,
   rel={{NREL}},
   config='[Kr] 4d4.0 5s1 5p0',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Nb.{{FCT}}-spn-rrkjus_psl.0.3.0.UPF',
   nconf=5
   configts(1)='4s2 4p6 4d4 5s1'
   configts(2)='4s2 4p6 4d4 5s0 5p1'
   configts(3)='4s2 4p6 4d4 5s0 5p0'
   configts(4)='4s2 4p6 4d3 5s2'
   configts(5)='4s2 4p6 4d5 5s0'
 /
