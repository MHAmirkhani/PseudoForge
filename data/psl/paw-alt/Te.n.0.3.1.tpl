 &input
   title='Te',
   zed=52.,
   rel={{NREL}},
   config='[Kr] 4d10.0 5s2.0 5p4.0 5d-2.0',
   iswitch=3,
   dft='{{GFUN}}'
 /
 &inputp
   lpaw=.true.,
   pseudotype=3,
   file_pseudopw='Te.{{FCT}}-n-kjpaw_psl.0.3.1.UPF',
   author='ADC (similar to GBRV)',
   lloc=-1,
   rcloc=2.1,
   which_augfun='PSQ',
   rmatch_augfun_nc=.true.,
   nlcc=.true.,
   new_core_ps=.true.,
   rcore=1.1,
   tm=.true.
 /
6
5S  1  0  2.00  0.00  1.70  2.10  0.0
5S  1  0  0.00  6.30  1.70  2.10  0.0
5P  2  1  4.00  0.00  1.70  2.10  0.0
5P  2  1  0.00  6.30  1.70  2.10  0.0
5D  3  2  0.00  0.50  1.70  2.60  0.0
5D  3  2  0.00  6.30  1.70  2.60  0.0
