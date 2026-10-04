 &input
   title='Xe q',
   zed=54.,
   rel={{NREL}},
   config='[Kr] 4d10.0 5s2.0 5p6.0 5d-2.0',
   iswitch=3,
   dft='{{GFUN}}'
 /
 &inputp
   pseudotype=3,
   file_pseudopw='Xe.{{FCT}}-n-rrkjus_psl.0.3.1.UPF',
   author='ADC',
   lloc=-1,
   rcloc=2.0,
   which_augfun ='PSQ',
   rmatch_augfun_nc= .true.,
   nlcc=.true.,
   tm=.true.
 /
6
5S  1  0  2.00  0.00  1.40  1.60  0.0
5S  1  0  0.00  0.50  1.40  1.60  0.0
5P  2  1  6.00  0.00  1.40  2.10  0.0
5P  2  1  0.00  0.20  1.40  2.10  0.0
4D  3  2 10.00  0.00  1.40  1.70  0.0
4D  3  2  0.00  0.30  1.40  1.70  0.0
