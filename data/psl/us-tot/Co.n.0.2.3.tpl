 &input
   title='Co b',
   zed=27.,
   rel={{NREL}},
   config='[Ar] 4s2 3d7 4p0',
   iswitch=3,
   dft='{{GFUN}}'
 /
 &inputp
   pseudotype=3,
   file_pseudopw='Co.{{FCT}}-n-rrkjus_psl.0.2.3.UPF',
   author='ADC',
   lloc=-1,
   rcloc=2.0,
   which_augfun ='PSQ',
   rmatch_augfun= 1.5,
   nlcc=.true.,
   new_core_ps=.true.,
   rcore=0.7,
   tm=.true.
 /
6
4S  1 0 2.00  0.00  1.40  2.10  0.0
4S  1 0 0.00  0.30  1.40  2.10  0.0
4P  2 1 0.00  0.00  1.40  2.20  0.0
4P  2 1 0.00  0.50  1.40  2.20  0.0
3D  3 2 7.00  0.00  1.40  1.90  0.0
3D  3 2 0.00 -0.40  1.40  1.90  0.0
