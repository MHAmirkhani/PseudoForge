 &input
   title='H',
   zed=1,
   rel={{NREL}},
   config='1s1 2p-1 2s-1',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/H.{{FCT}}-rrkjus_psl.1.0.0.UPF',
   nconf=3
   frozen_core={{FROZEN_CORE}},
   configts(1)='1s1'
   configts(2)='1s0.5 2s0 2p0'
   configts(3)='1s0.0 2s0.5 2p0'
 /
