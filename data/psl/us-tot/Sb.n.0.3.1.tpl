 &input
   title='Sb b',
   zed=51.,
   rel={{NREL}},
   config='[Kr] 4d10.0 5s2.0 5p3.0 5d-2.0',
   iswitch=3,
   dft='{{GFUN}}'
 /
 &inputp
   pseudotype=3,
   file_pseudopw='Sb.{{FCT}}-n-rrkjus_psl.0.3.1.UPF',
   author='ADC',
   lloc=-1,
   rcloc=2.2,
   which_augfun ='PSQ',
   rmatch_augfun= 1.9,
   nlcc=.true.,
   tm=.true.
 /
6
5S  1  0  2.00  0.00  1.90  2.20  0.0
5S  1  0  0.00  5.50  1.90  2.20  0.0
5P  2  1  3.00  0.00  1.90  2.30  0.0
5P  2  1  0.00  6.30  1.90  2.30  0.0
5D  3  2 -2.00  0.10  1.90  2.50  0.0
5D  3  2 -2.00  6.40  1.90  2.50  0.0
