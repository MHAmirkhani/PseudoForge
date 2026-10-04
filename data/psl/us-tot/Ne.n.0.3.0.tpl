 &input
   title='Ne q',
   zed=10.0,
   rel={{NREL}},
   config='1s2 2s2 2p6 3d-2',
   iswitch=3,
   dft='{{GFUN}}'
 /
 &inputp
   pseudotype=3,
   file_pseudopw='Ne.{{FCT}}-n-rrkjus_psl.0.3.0.UPF',
   author='ADC',
   lloc=2,
   which_augfun ='PSQ',
   rmatch_augfun=1.0,
   nlcc=.true.,
   new_core_ps=.true.,
   rcore=0.4,
   tm=.true.
 /
5
2S  1  0  2.00  0.00  1.40  1.50  0.0
2S  1  0  0.00  6.30  1.50  1.60  0.0
2P  2  1  6.00  0.00  1.20  1.50  0.0
2P  2  1  0.00 -0.90  1.20  1.50  0.0
3D  3  2 -2.00  0.15  1.10  1.10  0.0
