 &input
   title='Os q',
   zed=76.,
   rel={{NREL}},
   iswitch=3,
   config='[Xe] 4f14.0 5d6.0 6s2.0 6p0.0',
   dft='{{GFUN}}'
 /
 &inputp
   lpaw=.true.,
   pseudotype=3,
   file_pseudopw='Os.{{FCT}}-n-kjpaw_psl.0.2.3.UPF',
   author='ADC',
   lloc=-1,
   rcloc=2.4,
   which_augfun='BESSEL',
   rmatch_augfun=2.0,
   nlcc=.true.,
   tm=.true.
 /
6
6S  1  0  2.00  0.00  2.20  2.40  0.0
6S  1  0  0.00  0.40  2.20  2.40  0.0
6P  2  1  0.00  0.00  2.50  2.90  0.0
6P  2  1  0.00  1.60  2.50  2.90  0.0
5D  3  2  6.00  0.00  1.80  2.10  0.0
5D  3  2  0.00  0.30  1.80  2.10  0.0
