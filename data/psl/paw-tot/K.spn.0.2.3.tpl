 &input
   title='K b',
   zed=19.0,
   rel={{NREL}},
   config='[Ar] 3d-2 4s1 4p0',
   iswitch=3,
   dft='{{GFUN}}'
 /
 &inputp
   lpaw=.true.,
   pseudotype=3,
   file_pseudopw='K.{{FCT}}-spn-kjpaw_psl.0.2.3.UPF',
   author='ADC',
   lloc=-1,
   rcloc=2.2,
   which_augfun='PSQ',
   rmatch_augfun=1.6,
   nlcc=.true.,
   new_core_ps=.true.,
   rcore=0.9,
   tm=.true.
 /
6
3S  1  0  2.00  0.00  1.50  2.30  0.0
4S  2  0  1.00  0.00  1.00  1.70  0.0
3P  2  1  6.00  0.00  1.50  1.80  0.0
4P  3  1  0.00  6.00  1.50  1.80  0.0
3D  3  2 -2.00  0.10  1.70  2.10  0.0
3D  3  2 -2.00  1.30  1.70  2.10  0.0
