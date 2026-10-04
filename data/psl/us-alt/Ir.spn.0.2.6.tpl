 &input
   title='Ir',
   zed=77.,
   rel={{NREL}},
   config='[Xe] 4f14.0 5d7.0 6s2.0 6p0.0',
   iswitch=3,
   dft='{{GFUN}}'
 /
 &inputp
   pseudotype=3,
   file_pseudopw='Ir.{{FCT}}-spn-rrkjus_psl.0.2.6.UPF',
   author='ADC',
   lloc=-1,
   rcloc=2.2,
   which_augfun='PSQ',
   rmatch_augfun=0.99,
   nlcc=.true.,
   tm=.true.
 /
6
5S  1  0  2.00  0.00  0.80  1.60  0.0
6S  2  0  2.00  0.00  0.80  1.60  0.0
5P  2  1  6.00  0.00  1.00  1.60  0.0
6P  3  1  0.00  0.00  1.00  1.80  0.0
5D  3  2  7.00  0.00  1.80  2.30  0.0
5D  3  2  0.00 -0.30  1.80  2.30  0.0
