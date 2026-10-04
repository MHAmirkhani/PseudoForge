 &input
   title='Zn',
   zed=30.,
   rel={{NREL}},
   config='[Ar] 3d10.0 4s2.0 4p0.0',
   iswitch=3,
   dft='{{GFUN}}'
 /
 &inputp
   lpaw=.true.,
   pseudotype=3,
   file_pseudopw='Zn.{{FCT}}-spn-kjpaw_psl.0.3.1.UPF',
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
3S  1  0  2.00  0.00  1.00  1.25  0.0
4S  2  0  2.00  0.00  1.00  1.25  0.0
3P  2  1  6.00  0.00  1.10  1.15  0.0
4P  3  1  0.00  6.30  1.10  1.15  0.0
3D  3  2 10.00  0.00  0.90  1.35  0.0
3D  3  2  0.00 -0.30  0.90  1.35  0.0
