 &input
   title='Ti d',
   zed=22.0,
   rel={{NREL}},
   config='[Ar] 3d2.0 4s2 4p0',
   iswitch=3,
   dft='{{GFUN}}'
 /
 &inputp
   lpaw=.true.,
   pseudotype=3,
   file_pseudopw='Ti.{{FCT}}-spn-kjpaw_psl.0.3.1.UPF',
   author='ADC',
   lloc=-1,
   rcloc=2.1,
   which_augfun='PSQ',
   rmatch_augfun_nc=.true.,
   nlcc=.true.,
   new_core_ps=.true.,
   rcore=0.7,
   tm=.true.
 /
6
3S  1  0  2.00  0.00  0.75  1.70  0.0
4S  2  0  2.00  0.00  0.75  1.70  0.0
3P  2  1  6.00  0.00  0.75  1.80  0.0
4P  3  1  0.00  0.00  0.75  1.80  0.0
3D  3  2  2.00  0.00  0.75  1.70  0.0
3D  3  2 -2.00  0.80  0.75  1.70  0.0
