 &input
   title='Au',
   zed=79.,
   rel={{NREL}},
   config='[Xe] 4f14 5d10.0 6s1.0 6p0.0',
   iswitch=3,
   dft='{{GFUN}}'
 /
 &inputp
   pseudotype=3,
   file_pseudopw='Au.{{FCT}}-spn-rrkjus_psl.0.2.4.UPF',
   author='ADC',
   lloc=-2,
   rcloc=1.6,
   which_augfun='PSQ',
   rmatch_augfun=0.95
   nlcc=.true.,
   new_core_ps=.true.,
   rcore=1.0,
   tm=.true.
 /
6
5S  1  0  2.00  0.00  0.80  1.50  0.0
6S  2  0  1.00  0.00  0.80  1.60  0.0
5P  2  1  6.00  0.00  1.00  1.40  0.0
6P  3  1  0.00  0.00  1.00  1.90  0.0
5D  3  2 10.00  0.00  1.80  2.30  0.0
5D  3  2  0.00 -0.30  1.80  2.30  0.0
