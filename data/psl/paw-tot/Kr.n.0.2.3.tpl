 &input
   title='Kr q',
   zed=36.0,
   rel={{NREL}},
   config='[Ar] 3d10 4s2 4p6.00 4d-2.0',
   iswitch=3,
   dft='{{GFUN}}'
 /
 &inputp
   lpaw=.true.,
   pseudotype=3,
   file_pseudopw='Kr.{{FCT}}-n-kjpaw_psl.0.2.3.UPF',
   author='ADC',
   lloc=-1,
   rcloc=1.8,
   which_augfun='PSQ',
   rmatch_augfun=1.3,
   nlcc=.true.,
   new_core_ps=.true.,
   rcore=1.4,
   tm=.true.
 /
6
4S  1  0  2.00  0.00  1.70  1.80  0.0
4S  1  0  0.00  0.30  1.10  1.80  0.0
4P  2  1  6.00  0.00  1.60  1.70  0.0
4P  2  1  0.00  0.20  1.60  1.70  0.0
4D  3  2 -2.00  0.30  1.70  2.00  0.0
4D  3  2 -2.00  0.70  1.70  2.00  0.0
