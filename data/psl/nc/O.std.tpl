 &input
   title='O',
   zed=8,
   rel={{NREL}},
   config='[He] 2s2 2p4 3d-2',
   iswitch=3,
   dft='{{GFUN}}'
 /
 &inputp
   pseudotype=2,
   file_pseudopw='O.{{FCT}}-nc.UPF',
   author='TM',
   lloc=0,
   tm=.true.
 /
2
2P  2  1  4.00  0.00  1.10  1.10  0.0
2S  1  0  2.00  0.00  1.10  1.10  0.0
