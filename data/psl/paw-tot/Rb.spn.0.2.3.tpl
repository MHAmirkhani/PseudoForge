 &input
   title='Rb d',
   zed=37.0,
   rel={{NREL}},
   config='[Kr] 4d-2.0 5s1 5p0',
   iswitch=3,
   dft='{{GFUN}}'
 /
 &inputp
   lpaw=.true.,
   pseudotype=3,
   file_pseudopw='Rb.{{FCT}}-spn-kjpaw_psl.0.2.3.UPF',
   author='ADC',
   lloc=-1,
   rcloc=2.2,
   which_augfun='PSQ',
   rmatch_augfun=1.3,
   nlcc=.true.,
   rcore=1.2,
   tm=.true.
 /
6
4S  1  0  2.00  0.00  1.50  1.70  0.0
5S  2  0  1.00  0.00  1.10  1.70  0.0
4P  2  1  6.00  0.00  1.50  1.80  0.0
5P  3  1  0.00  0.00  1.50  1.80  0.0
4D  3  2 -2.00  0.10  2.00  2.10  0.0
4D  3  2 -2.00  0.30  2.00  2.10  0.0
