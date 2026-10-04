 &input
   title='Be',
   zed=4.0,
   rel={{NREL}},
   config='[He] 2s2.0 2p0.0',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Be.{{FCT}}-s-kjpaw_psl.1.0.0.UPF',
   nconf=5,
   frozen_core={{FROZEN_CORE}},
   configts(1)='1s2 2s2'
   configts(2)='1s2 2s1 2p1'
   configts(3)='1s2 2s1 2p0'
   configts(4)='1s2 2s0.5 2p1'
   configts(5)='1s2 2s0.5 2p0'
 /
