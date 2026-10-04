 &input
   title='He',
   zed=2.,
   rel={{NREL}},
   config='1s2 2p-2',
   iswitch=3,
   dft='{{GFUN}}'
 /
 &inputp
   lpaw=.true.,
   pseudotype=3,
   file_pseudopw='He.{{FCT}}-kjpaw_psl.1.0.0.UPF',
   author='ADC',
   lloc=-1,
   rcloc=0.6
   which_augfun='PSQ',
   rmatch_augfun_nc=.true.,
   tm=.true.
 /
2
1S  1  0  2.00  0.00  0.90  1.10  0.0
1S  1  0  0.00  0.05  0.90  1.10  0.0
