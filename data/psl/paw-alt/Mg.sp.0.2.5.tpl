 &input
   title='Mg',
   zed=12.0,
   rel={{NREL}},
   config='[Ne] 3s1.5 3p0 3d-2',
   iswitch=3,
   dft='{{GFUN}}'
 /
 &inputp
   lpaw=.true.,
   pseudotype=3,
   file_pseudopw='Mg.{{FCT}}-sp-kjpaw_psl.0.2.5.UPF',
   author='ADC',
   rcloc=1.5
   lloc=-1,
   which_augfun='PSQ',
   rmatch_augfun=0.8,
   tm=.true.
 /
6
2S  1  0  2.00  0.00  0.50  1.20  0.0
3S  2  0  1.50  0.00  0.50  1.20  0.0
2P  2  1  6.00  0.00  0.50  1.30  0.0
3P  3  1  0.00  0.00  0.50  1.30  0.0
3D  3  2 -2.00  0.10  1.10  2.30  0.0
3D  3  2 -2.00  0.30  1.10  2.30  0.0
