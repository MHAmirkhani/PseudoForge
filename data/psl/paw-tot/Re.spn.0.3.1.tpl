 &input
   title='Re q',
   zed=75.0,
   rel={{NREL}},
   config='[Xe] 4f14 5d5.0 6s2 6p0',
   iswitch=3,
   dft='{{GFUN}}'
 /
 &inputp
   lpaw=.true.,
   pseudotype=3,
   file_pseudopw='Re.{{FCT}}-spn-kjpaw_psl.0.3.1.UPF',
   author='ADC (inspired GBRV)',
   lloc=-1,
   rcloc=2.1,
   which_augfun='BESSEL',
   rmatch_augfun=1.4,
   nlcc=.true.,
   new_core_ps=.true.,
   rcore=1.1,
   tm=.true.
 /
6
5S  1  0  2.00  0.00  0.80  1.40  0.0
6S  2  0  2.00  0.00  0.80  1.40  0.0
5P  2  1  6.00  0.00  1.00  1.50  0.0
6P  3  1  0.00  0.00  1.00  1.50  0.0
5D  3  2  5.00  0.00  1.20  1.55  0.0
5D  3  2 -2.00  0.30  1.20  1.55  0.0
