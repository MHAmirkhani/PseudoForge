 &input
   title='Be',
   zed=4.,
   rel={{NREL}},
   config='[He] 2s2 2p0',
   iswitch=3,
   dft='{{GFUN}}'
 /
 &inputp
   lpaw=.false.,
   pseudotype=3,
   file_pseudopw='Be.{{FCT}}-sl-rrkjus_psl.1.0.0.UPF',
   author='ADC',
   lloc=-1,
   rcloc=0.8,
   which_augfun='PSQ',
   rmatch_augfun_nc=.true.,
   tm=.true.
 /
4
1S  1  0  2.00  0.00  0.50  1.30  0.0
2S  2  0  2.00  0.00  0.50  1.30  0.0
2P  2  1  0.00  0.00  0.90  1.70  0.0
2P  2  1  0.00  1.50  0.90  1.70  0.0
