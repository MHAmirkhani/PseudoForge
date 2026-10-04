 &input
   title='O',
   zed=8,
   rel={{NREL}},
   config='[He] 2s2 2p4 3d-2',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/O.{{FCT}}-nl-rrkjus_psl.1.0.0.UPF',
   nconf=5,
   frozen_core={{FROZEN_CORE}},
   configts(1)='2s2 2p4'
   configts(2)='2s2 2p3'
   configts(3)='2s2 2p2'
   configts(4)='2s1 2p5'
   configts(5)='2s1 2p4'
 /
