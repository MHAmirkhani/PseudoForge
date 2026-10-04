 &input
   title='B',
   zed=5.0,
   rel={{NREL}},
   config='1s2.0 2s2.0 2p1.0 3d-2.0',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/B.{{FCT}}-n-rrkjus_psl.1.0.0.UPF',
   nconf=5,
   frozen_core={{FROZEN_CORE}},
   configts(1)='2s2 2p1'
   configts(2)='2s2 2p1'
   configts(3)='2s2 2p0'
   configts(4)='2s1 2p2'
   configts(5)='2s1 2p1'
 /
