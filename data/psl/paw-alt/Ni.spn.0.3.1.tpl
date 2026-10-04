 &input
   title='Ni',
   zed=28.,
   rel={{NREL}},
   config='[Ar] 3d8.0 4s2.0 4p0.0',
   iswitch=3,
   dft='{{GFUN}}'
 /
 &inputp
   lpaw=.true.,
   pseudotype=3,
   file_pseudopw='Ni.{{FCT}}-spn-kjpaw_psl.0.3.1.UPF',
   author='ADC',
   lloc=-1,
   rcloc=1.2,
   which_augfun='PSQ',
   rmatch_augfun_nc=.true.,
   nlcc=.true.,
   rcore=0.65,
   tm=.true.
 /
6
3S  1  0  2.00  0.00  1.00  1.30  0.0
4S  2  0  2.00  0.00  1.00  1.30  0.0
3P  2  1  6.00  0.00  1.00  1.35  0.0
4P  3  1  0.00  0.00  1.00  1.35  0.0
3D  3  2  8.00  0.00  1.00  1.30  0.0
3D  3  2  0.00 -2.00  1.00  1.30  0.0
