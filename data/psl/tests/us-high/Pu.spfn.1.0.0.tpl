 &input
   title='Pu',
   zed=94.0,
   rel={{NREL}},
   config='[Rn] 6d0.0 7s2.0 7p0. 5f6.0',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Pu.{{FCT}}-spfn-rrkjus_psl.1.0.0.UPF',
   nconf=5,
   frozen_core={{FROZEN_CORE}},
   configts(1)='6s2 6p6 7s2 7p0 6d1.5 5f4.5 '
   configts(2)='6s2 6p6 7s2 7p0. 6d0 5f5 '
   configts(3)='6s2 6p6 7s2 7p0. 6d1 5f4 '
   configts(4)='6s2 6p6 7s1 7p0. 6d1 5f5.0 '
   configts(5)='6s2 6p6 7s1 7p0. 6d1 5f5 '
 /
