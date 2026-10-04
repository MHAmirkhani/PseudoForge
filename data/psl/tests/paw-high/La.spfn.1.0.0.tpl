 &input
   title='La',
   zed=57.0,
   rel={{NREL}},
   config='[Xe] 4f0 5d1.0 6s2 6p1',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/La.{{FCT}}-spfn-kjpaw_psl.1.0.0.UPF',
   nconf=5,
   frozen_core={{FROZEN_CORE}},
   configts(1)='5s2  5p6 6s2   6p0   5d1 4f0 '
   configts(2)='5s2  5p6 6s1.5 6p0.5 5d1 4f0 '
   configts(3)='5s2  5p6 6s1   6p0. 5d1 4f0 '
   configts(4)='5s2  5p6 6s0   6p0  5d1 4f0 '
   configts(5)='5s2  5p6 6s1   6p1. 5d1 4f0 '
 /
