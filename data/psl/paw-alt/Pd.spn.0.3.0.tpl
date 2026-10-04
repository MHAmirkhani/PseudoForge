 &input
   title='Pd',
   zed=46.,
   rel={{NREL}},
   config='[Kr] 4d10. 5s0.0 5p0.0',
   iswitch=3,
   dft='{{GFUN}}'
 /
 &inputp
   lpaw=.true.,
   pseudotype=3,
   file_pseudopw='Pd.{{FCT}}-spn-kjpaw_psl.0.3.0.UPF',
   author='ADC',
   lloc=-1,
   rcloc=1.4,
   which_augfun='PSQ',
   rmatch_augfun_nc=.true.,
   nlcc=.true.,
   tm=.true.
 /
6
4S  1  0  2.00  0.00  1.20  1.70  0.0
5S  2  0  0.00  0.00  1.20  1.30  0.0
4P  2  1  6.00  0.00  0.90  1.70  0.0
5P  3  1  0.00  0.00  0.90  1.30  0.0
4D  3  2 10.00  0.00  0.80  1.80  0.0
4D  3  2 -2.00  0.30  0.80  1.80  0.0
