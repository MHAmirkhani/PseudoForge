 &input
   title='Li',
   zed=3.0,
   rel={{NREL}},
   config='1s2 2s1 2p0 3d-2',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Li.{{FCT}}-sl-kjpaw_psl.1.0.0.UPF',
   nconf=4
   frozen_core={{FROZEN_CORE}},
   configts(1)='1s2 2s1'
   configts(2)='1s2 2s0.5 2p0'
   configts(3)='1s2 2s0 2p0'
   configts(4)='1s2 2s0 2p1'
 /
