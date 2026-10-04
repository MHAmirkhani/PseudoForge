 &input
   title='C',
   zed=6,
   rel={{NREL}},
   config='[He] 2s2 2p2 3d-2',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/C.{{FCT}}-n-kjpaw_psl.0.1.UPF',
   nconf=5,
   configts(1)='2s2 2p2'
   configts(2)='2s2 2p1'
   configts(3)='2s2 2p0'
   configts(4)='2s1 2p2'
   configts(5)='2s1 2p3'
 /
