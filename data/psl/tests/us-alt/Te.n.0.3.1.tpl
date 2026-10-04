 &input
   title='Te',
   zed=52.,
   rel={{NREL}},
   config='[Kr] 4d10.0 5s2.0 5p4.0 5d0.0',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Te.{{FCT}}-n-rrkjus_psl.0.3.1.UPF',
   nconf=5
   configts(1)='5s2 5p4'
   configts(2)='5s2 5p3 5d0'
   configts(3)='5s2 5p3 5d0.5'
   configts(4)='5s1 5p4 5d0'
   configts(5)='5s1 5p4 5d0.5'
 /
