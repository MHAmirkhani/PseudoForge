 &input
   title='Mg',
   zed=12.0,
   rel={{NREL}},
   config='[Ne] 3s2.0 3p0 3d-2',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Mg.{{FCT}}-spnl-kjpaw_psl.1.0.0.UPF',
   nconf=5
   frozen_core={{FROZEN_CORE}},
   configts(1)='2s2 2p6 3s2'
   configts(2)='2s2 2p6 3s1.5 3p0'
   configts(3)='2s2 2p6 3s1 3p0.5'
   configts(4)='2s2 2p6 3s1 3p0'
   configts(5)='2s2 2p6 3s1 3p0'
 /
