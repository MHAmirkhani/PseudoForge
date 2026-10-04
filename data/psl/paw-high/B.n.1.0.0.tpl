 &input
   title='B',
   zed=5.,
   rel={{NREL}},
   config='[He] 2s2 2p1',
   iswitch=3,
   dft='{{GFUN}}'
 /
 &inputp
   lpaw=.true.,
   pseudotype=3,
   file_pseudopw='B.{{FCT}}-n-kjpaw_psl.1.0.0.UPF',
   author='ADC',
   lloc=-1,
   rcloc=1.2
   which_augfun='PSQ',
   rmatch_augfun_nc=.true.,
   nlcc=.true.,
   new_core_ps=.true.,
   rcore=0.9,
   tm=.true.
 /
4
2S  1  0  2.00  0.00  1.00  1.20  0.0
2S  1  0  0.00  3.00  1.00  1.20  0.0
2P  2  1  1.00  0.00  1.00  1.40  0.0
2P  2  1  0.00  1.50  1.00  1.40  0.0
