 &input
   title='Co',
   zed=27.,
   rel={{NREL}},
   config='[Ar] 3d7.0 4s2.0 4p0.0',
   iswitch=3,
   dft='{{GFUN}}'
 /
 &inputp
   lpaw=.true.,
   pseudotype=3,
   file_pseudopw='Co.{{FCT}}-spn-kjpaw_psl.0.3.1.UPF',
   author='ADC',
   lloc=-1,
   rcloc=1.1,
   which_augfun='PSQ',
   rmatch_augfun_nc=.true.,
   nlcc=.true.,
   rcore=0.65,
   tm=.true.
 /
6
3S  1  0  2.00  0.00  1.10  1.40  0.0
4S  2  0  2.00  0.00  1.10  1.40  0.0
3P  2  1  6.00  0.00  0.90  1.30  0.0
4P  3  1  0.00  6.30  0.90  1.30  0.0
3D  3  2  7.00  0.00  1.10  1.40  0.0
3D  3  2  0.00 -2.00  1.10  1.40  0.0
