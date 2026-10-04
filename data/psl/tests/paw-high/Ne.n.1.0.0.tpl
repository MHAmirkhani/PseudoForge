 &input
   title='Ne',
   zed=10.0,
   rel={{NREL}},
   config='1s2 2s2 2p6 3d-2',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Ne.{{FCT}}-n-kjpaw_psl.1.0.0.UPF',
   nconf=5
   frozen_core={{FROZEN_CORE}},
   configts(1)='2s2 2p6'
   configts(2)='2s2 2p5 3d0 '
   configts(3)='2s2 2p5 3d0.5'
   configts(4)='2s1 2p6 3d0'
   configts(5)='2s1 2p5 3d0'
 /
