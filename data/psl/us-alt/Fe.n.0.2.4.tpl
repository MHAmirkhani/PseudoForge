 &input
   title='Fe',
   zed=26.,
   rel={{NREL}},
   config='[Ar] 4s1.7 3d6.3 4p0',
   iswitch=3,
   dft='{{GFUN}}'
 /
 &inputp
   pseudotype=3,
   file_pseudopw='Fe.{{FCT}}-n-rrkjus_psl.0.2.4.UPF',
   author='ADC',
   lloc=-1,
   rcloc=2.1,
   which_augfun='PSQ',
   rmatch_augfun=1.3,
   nlcc=.true.,
   new_core_ps=.true.,
   rcore=1.2,
   tm=.true.
 /
6
4S 1 0 1.70  0.00  1.70  2.20  0.0
4S 1 0 0.00  2.30  1.50  2.20  0.0
4P 2 1 0.00  0.00  1.90  2.20  0.0
4P 2 1 0.00  2.50  1.50  2.20  0.0
3D 3 2 6.30  0.00  1.50  1.80  0.0
3D 3 2 0.00 -0.30  0.70  1.80  0.0
