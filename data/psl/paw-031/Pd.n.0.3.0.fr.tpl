 &input
   title='Pd',
   zed=46.,
   rel={{NREL}},
   config='[Kr] 4d10. 5s0. 5p0.0',
   iswitch=3,
   dft='{{GFUN}}'
 /
 &inputp
   lpaw=.true.,
   pseudotype=3,
   file_pseudopw='Pd.{{FCT}}-n-kjpaw_psl.0.3.0.UPF',
   author='ADC',
   lloc=-1,
   rcloc=2.1,
   which_augfun='PSQ',
   rmatch_augfun=0.85,
   nlcc=.true.,
   tm=.true.
 /
6
5S  1  0  0.00  0.00  2.10  2.30  0.0
5S  1  0  0.00  5.50  2.10  2.30  0.0
5P  2  1  0.00  0.00  2.20  2.60  0.0
5P  2  1  0.00  6.30  2.20  2.60  0.0
4D  3  2 10.00  0.00  1.70  1.90  0.0
4D  3  2  0.00  4.30  1.70  1.90  0.0
