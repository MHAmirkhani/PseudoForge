 &input
   title='Fe',
   zed=26.,
   rel={{NREL}},
   config='[Ar] 4s1.7 3d6.3 4p0',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Fe.{{FCT}}-n-kjpaw_psl.0.2.4.UPF',
   nconf=5
   configts(1)='3d6 4s2'
   configts(2)='3d6 4s1 4p0'
   configts(3)='3d6 4s1 4p1'
   configts(4)='3d7 4s1'
   configts(5)='3d7 4s0 4p1'
 /
