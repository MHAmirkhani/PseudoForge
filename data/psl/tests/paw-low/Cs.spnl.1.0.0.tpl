 &input
   title='Cs',
   zed=55.0,
   rel={{NREL}},
   config='[Xe] 5d0.0 6s1 6p0',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Cs.{{FCT}}-spnl-kjpaw_psl.1.0.0.UPF',
   nconf=5
   frozen_core={{FROZEN_CORE}},
   configts(1)='5s2 5p6 6s1'
   configts(2)='5s2 5p6 6s0 6p1'
   configts(3)='5s2 5p6 6s0.5 6p0'
   configts(4)='5s2 5p6 6s0.5 6p0.5'
   configts(5)='5s2 5p6 6s0 6p0 5d1'
 /
