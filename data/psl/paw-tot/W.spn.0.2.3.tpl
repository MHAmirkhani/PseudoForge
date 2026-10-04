 &input
   title='W c',
   zed=74.0,
   rel={{NREL}},
   config='[Xe] 4f14 5d4.0 6s2 6p0',
   iswitch=3,
   dft='{{GFUN}}'
 /
 &inputp
   lpaw=.true.,
   pseudotype=3,
   file_pseudopw='W.{{FCT}}-spn-kjpaw_psl.0.2.3.UPF',
   author='ADC',
   lloc=-1,
   rcloc=2.4,
   which_augfun='BESSEL',
   rmatch_augfun=1.3,
   nlcc=.true.,
   new_core_ps=.true.,
   rcore=1.2,
   tm=.true.
 /
6
5S  1  0  2.00  0.00  1.40  1.50  0.0
6S  2  0  2.00  0.00  1.10  1.50  0.0
5P  2  1  6.00  0.00  1.50  1.70  0.0
6P  3  1  0.00  0.00  1.30  1.70  0.0
5D  3  2  4.00  0.00  1.70  1.90  0.0
5D  3  2 -2.00  0.30  1.70  1.90  0.0
