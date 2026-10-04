 &input
   title='B',
   zed=5.0,
   rel={{NREL}},
   config='1s2.0 2s2.0 2p1.0 3d-2.0',
   iswitch=3,
   dft='{{GFUN}}'
 /
 &inputp
   pseudotype=2,
   file_pseudopw='B.{{FCT}}-nc.UPF',
   author='TM',
   lloc=0,
   tm=.true.
 /
2
2P  2  1  1.00  0.00  1.40  1.40  0.0
2S  1  0  2.00  0.00  1.40  1.40  0.0
