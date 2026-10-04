 &input
   title='Au',
   zed=79.,
   rel={{NREL}},
   config='[Xe] 4f14 6s1 6p0 5d10',
   iswitch=3,
   dft='{{GFUN}}'
 /
 &inputp
   lpaw=.true.,
   pseudotype=3,
   file_pseudopw='Au.{{FCT}}-spn-kjpaw_psl.1.0.0.UPF',
   author='ADC',
   lloc=-1,
   rcloc=1.4,
   which_augfun='PSQ',
   rmatch_augfun_nc=.true.,
   nlcc=.true.,
   new_core_ps=.true.,
   rcore=1.2,
   tm=.true.
 /
6
5S  1  0  2.00  0.00  0.90  1.50  0.0
6S  2  0  1.00  0.00  0.90  1.50  0.0
5P  2  1  6.00  0.00  0.90  1.30  0.0
6P  3  1  0.00 -2.50  0.90  1.30  0.0
5D  3  2 10.00  0.00  1.40  1.60  0.0
5D  3  2  0.00  0.05  1.40  1.60  0.0
