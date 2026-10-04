 &input
   title='Xe',
   zed=54.,
   rel={{NREL}},
   config='[Kr] 4d10.0 5s2.0 5p6.0 5d-2.0',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Xe.{{FCT}}-n-kjpaw_psl.0.3.1.UPF',
   nconf=5
   configts(1)='4d10 5s2 5p6'
   configts(2)='4d10 5s2 5p5 5d0.5'
   configts(3)='4d10 5s2 5p5 5d0'
   configts(4)='4d10 5s1 5p6 5d0'
   configts(5)='4d10 5s1 5p5 5d0.5'
 /
