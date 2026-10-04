 &input
   title='Be',
   zed=4.0,
   rel={{NREL}},
   config='1s2 2s2 2p0',
   iswitch=3,
   dft='{{GFUN}}'
 /
 &inputp
   lpaw=.true.,
   pseudotype=3,
   file_pseudopw='Be.{{FCT}}-s-kjpaw_psl.0.3.1.UPF',
   author='ADC',
   lloc=-1,
   rcloc=0.8,
   which_augfun='PSQ',
   rmatch_augfun_nc=.true.,
   tm=.true.
 /
4
1S  1  0  2.00  0.00  1.00  1.20  0.0
2S  2  0  2.00  0.00  1.00  1.20  0.0
2P  2  1  0.00  0.00  0.90  1.20  0.0
2P  2  1  0.00  1.50  0.90  1.20  0.0
