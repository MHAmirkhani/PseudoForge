 &input
   title='Cs e',
   zed=55.0,
   rel={{NREL}},
   config='[Xe] 5d0.0 6s1 6p0',
   iswitch=3,
   dft='{{GFUN}}'
 /
 &inputp
   lpaw=.true.,
   pseudotype=3,
   file_pseudopw='Cs.{{FCT}}-spn-kjpaw_psl.0.2.3.UPF',
   author='ADC',
   lloc=-1,
   rcloc=2.2,
   which_augfun='BESSEL',
   rmatch_augfun=2.3,
   nlcc=.true.,
   new_core_ps=.true.,
   rcore=1.6,
   tm=.true.
 /
6
5S  1  0  2.00  0.00  1.50  1.90  0.0
6S  2  0  1.00  0.00  1.50  1.90  0.0
5P  2  1  6.00  0.00  1.50  2.30  0.0
6P  3  1  0.00  4.00  1.50  2.30  0.0
5D  3  2 -2.00  0.30  1.90  2.10  0.0
5D  3  2 -2.00  4.30  1.90  2.10  0.0
