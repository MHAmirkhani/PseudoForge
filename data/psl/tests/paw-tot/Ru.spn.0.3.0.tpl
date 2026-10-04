 &input
   title='Ru',
   zed=44.,
   rel={{NREL}},
   config='[Kr] 4d6.0 5s2.0 5p0.0',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Ru.{{FCT}}-spn-kjpaw_psl.0.3.0.UPF',
   nconf=5,
   configts(1)='4s2 4p6 4d6 5s2'
   configts(2)='4s2 4p6 4d6 5s1 5p0'
   configts(3)='4s2 4p6 4d6 5s0 5p1'
   configts(4)='4s2 4p6 4d7 5s1 5p0'
   configts(5)='4s2 4p6 4d5 5s2 5p0'
 /
