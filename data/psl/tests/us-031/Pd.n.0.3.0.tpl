 &input
   title='Pd',
   zed=46.,
   rel={{NREL}},
   config='[Kr] 4d10. 5s0. 5p0.0',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Pd.{{FCT}}-n-rrkjus_psl.0.3.0.UPF',
   nconf=5,
   configts(1)='4d10 5s0.0'
   configts(2)='4d9.5 5s0.5'
   configts(3)='4d9.5 5s0 5p0.5'
   configts(4)='4d9 5s1 5p0'
   configts(5)='4d9 5s0 5p1'
 /
