 &input
   title='N',
   zed=7.,
   rel={{NREL}},
   config='[He] 2s2 2p3 3d-2',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/N.{{FCT}}-n-kjpaw_psl.1.0.0.UPF',
   nconf=5,
   frozen_core={{FROZEN_CORE}},
   configts(1)='2s2 2p3'
   configts(2)='2s2 2p2'
   configts(3)='2s2 2p1'
   configts(4)='2s1 2p4'
   configts(5)='2s1 2p3'
 /
