 &input
   title='He',
   zed=2.0,
   rel={{NREL}},
   config='1s2 2s-2 2p-2',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/He.{{FCT}}-rrkjus_psl.1.0.0.UPF',
   nconf=5
   frozen_core={{FROZEN_CORE}},
   configts(1)='1s2'
   configts(2)='1s1.5 2p0'
   configts(3)='1s1.5 2s0'
   configts(4)='1s1.5 2s0.5'
   configts(5)='1s1.5 2s0 2p0.5'
 /
