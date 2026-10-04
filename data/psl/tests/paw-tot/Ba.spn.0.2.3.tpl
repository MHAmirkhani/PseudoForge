 &input
   title='Ba',
   zed=56.0,
   rel={{NREL}},
   config='[Xe] 5d0.0 6s2 6p0',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Ba.{{FCT}}-spn-kjpaw_psl.0.2.3.UPF',
   nconf=5
   configts(1)='5s2 5p6 6s2'
   configts(2)='5s2 5p6 6s1.5 6p0'
   configts(3)='5s2 5p6 6s1 6p1'
   configts(4)='5s2 5p6 6s0.5 6p1'
   configts(5)='5s2 5p6 6s1. 6p0 5d0'
 /
