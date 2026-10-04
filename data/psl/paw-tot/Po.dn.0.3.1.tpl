 &input
   title='Po q',
   zed=84.,
   rel={{NREL}},
   config='[Xe] 4f14.0 5d10.0 6s2.0 6p4.0 6d-2',
   iswitch=3,
   dft='{{GFUN}}'
 /
 &inputp
   lpaw=.true.,
   pseudotype=3,
   file_pseudopw='Po.{{FCT}}-dn-kjpaw_psl.0.3.1.UPF',
   author='ADC',
   lloc=-1,
   rcloc=1.8,
   which_augfun='PSQ',
   rmatch_augfun_nc=.true.,
   nlcc=.true.,
   new_core_ps=.true.,
   rcore=1.2,
   tm=.true.
 /
6
6S  1  0  2.00  0.00  1.10  2.00  0.0
6S  2  0  0.00  1.00  1.10  2.00  0.0
6P  2  1  4.00  0.00  1.30  2.20  0.0
6P  3  1  0.00  7.00  1.30  2.20  0.0
5D  3  2 10.00  0.00  0.90  1.60  0.0
5D  3  2 -2.00 -1.50  0.90  1.60  0.0
