 &input
   title='F',
   zed=9.0,
   rel={{NREL}},
   config='1s2.0 2s2.0 2p5.0',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/F.{{FCT}}-n-kjpaw_psl.0.1.UPF',
   nconf=5
   configts(1)='2s2 2p5'
   configts(2)='2s2 2p4'
   configts(3)='2s2 2p3'
   configts(4)='2s1 2p5'
   configts(5)='2s1 2p6'
 /
