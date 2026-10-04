 &input
   title='Na',
   zed=11.0,
   rel={{NREL}},
   config='[Ne] 3s0.5 3p0 3d-2',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Na.{{FCT}}-spn-kjpaw_psl.0.2.UPF',
   nconf=4
   configts(1)='2s2 2p6 3s1'
   configts(2)='2s2 2p6 3s0.5 3p0'
   configts(3)='2s2 2p6 3s0 3p0.5'
   configts(4)='2s2 2p6 3s0 3p0'
 /
