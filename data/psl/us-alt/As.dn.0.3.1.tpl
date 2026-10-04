 &input
   title='As',
   zed=33.,
   rel={{NREL}},
   config='[Ar] 3d10.0 4s2.0 4p3.0',
   iswitch=3,
   dft='{{GFUN}}'
 /
 &inputp
   pseudotype=3,
   file_pseudopw='As.{{FCT}}-dn-rrkjus_psl.0.3.1.UPF',
   author='ADC',
   lloc=-1,
   rcloc=1.9,
   which_augfun='PSQ',
   rmatch_augfun_nc=.true.,
   nlcc=.true.,
   rcore=0.9,
   tm=.true.
 /
6
4S  1  0  2.00  0.00  1.30  2.00  0.0
4S  1  0  0.00  3.10  1.30  2.00  0.0
4P  2  1  3.00  0.00  1.30  2.20  0.0
4P  2  1  0.00  6.30  1.30  2.20  0.0
3D  3  2 10.00  0.00  1.30  1.50  0.0
3D  3  2  0.00  0.40  1.30  1.50  0.0
