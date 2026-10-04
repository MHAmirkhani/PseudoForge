 &input
   title='Sc',
   zed=21.0,
   rel={{NREL}},
   config='[Ar] 3d1.0 4s2 4p0',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Sc.{{FCT}}-spn-rrkjus_psl.0.2.3.UPF',
   nconf=5
   configts(1)='3s2 3p6 3d1 4s2'
   configts(2)='3s2 3p6 3d1 4s1 4p1' 
   configts(3)='3s2 3p6 3d1 4s1 4p0'
   configts(4)='3s2 3p6 3d0 4s2 4p0'
   configts(5)='3s2 3p6 3d0 4s1 4p1'
 /
