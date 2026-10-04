 &input
   title='Sn',
   zed=50.,
   rel={{NREL}},
   config='[Kr] 4d10.0 5s2.0 5p2.0',
   iswitch=3,
   dft='{{GFUN}}'
 /
 &inputp
   pseudotype=3,
   file_pseudopw='Sn.{{FCT}}-dn-rrkjus_psl.0.2.UPF',
   author='ADC',
   lloc=-1,
   rcloc=2.3,
   which_augfun='PSQ',
   rmatch_augfun=1.8,
   nlcc=.true.,
   rcore=1.2,
   tm=.true.
 /
6
5S  1  0  2.00  0.00  2.00  2.20  0.0 
5S  1  0  0.00  3.10  2.00  2.20  0.0   
5P  2  1  2.00  0.00  2.30  2.50  0.0 
5P  2  1  0.00  6.30  2.30  2.50  0.0 
4D  3  2 10.00  0.00  1.70  2.40  0.0 
4D  3  2  0.00  4.30  1.70  2.40  0.0 
