 &input
   title='Mg',
   zed=12.0,
   rel={{NREL}},
   config='[Ne] 3s1.5 3p0 3d-2',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Mg.{{FCT}}-sp-rrkjus_psl.0.2.5.UPF',
   nconf=4
   configts(1)='2s2 2p6 3s2'
   configts(2)='2s2 2p6 3s1 3p1'
   configts(3)='2s2 2p6 3s0 3p2'
   configts(4)='2s2 2p6 3s0 3p1'
 /
