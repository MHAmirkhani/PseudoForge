 &input
   title='Ac',
   zed=89.0,
   rel={{NREL}},
   config='[Rn] 6d1.0 7s2.0 7p0. 5f-1',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Ac.{{FCT}}-spfn-rrkjus_psl.1.0.0.UPF',
   nconf=5,
   frozen_core={{FROZEN_CORE}},
   configts(1)='6s2 6p6 7s2 7p0 6d1 '
   configts(2)='6s2 6p6 7s1.5 7p0.0  6d1 '
   configts(3)='6s2 6p6 7s1 7p0. 6d1 5f0 '
   configts(4)='6s2 6p6 7s1 7p0. 6d0 5f0.6 '
   configts(5)='6s2 6p6 7s1 7p1. 6d0 5f0. '
 /
