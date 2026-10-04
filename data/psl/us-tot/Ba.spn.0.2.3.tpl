 &input
   title='Ba d',
   zed=56.0,
   rel={{NREL}},
   config='[Xe] 5d0.0 6s2 6p0',
   iswitch=3,
   dft='{{GFUN}}'
 /
 &inputp
   pseudotype=3,
   file_pseudopw='Ba.{{FCT}}-spn-rrkjus_psl.0.2.3.UPF',
   author='ADC',
   lloc=-1,
   rcloc=2.6,
   which_augfun='PSQ',
   rmatch_augfun=1.5,
   nlcc=.true.,
   rcore=1.5,
   tm=.true.
 /
6
5S  1  0  2.00  0.00  1.50  1.80  0.0
6S  2  0  2.00  0.00  1.50  1.80  0.0
5P  2  1  6.00  0.00  1.50  1.70  0.0
6P  3  1  0.00  0.00  1.50  1.70  0.0
5D  3  2 -2.00  0.10  2.00  2.30  0.0
5D  3  2 -2.00  0.30  2.00  2.30  0.0
