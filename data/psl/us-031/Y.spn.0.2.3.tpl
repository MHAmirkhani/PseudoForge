 &input
   title='Y',
   zed=39.0,
   rel={{NREL}},
   config='[Kr] 4d1.0 5s2 5p0',
   iswitch=3,
   dft='{{GFUN}}'
 /
 &inputp
   pseudotype=3,
   file_pseudopw='Y.{{FCT}}-spn-rrkjus_psl.0.2.3.UPF',
   author='ADC',
   lloc=-1,
   rcloc=2.4,
   which_augfun='PSQ',
   rmatch_augfun=1.2,
   nlcc=.true.,
   rcore=0.9,
   tm=.true.
 /
6
4S  1  0  2.00  0.00  1.50  1.60  0.0
5S  2  0  2.00  0.00  1.10  1.60  0.0
4P  2  1  6.00  0.00  1.50  1.70  0.0
5P  3  1  0.00  0.00  1.50  1.70  0.0
4D  3  2  1.00  0.00  1.70  1.90  0.0
4D  3  2 -2.00  0.30  1.70  1.90  0.0
