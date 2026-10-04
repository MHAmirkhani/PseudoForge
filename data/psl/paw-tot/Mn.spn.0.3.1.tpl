 &input
   title='Mn c',
   zed=25.0,
   rel={{NREL}},
   config='[Ar] 3d5.0 4s2 4p0',
   iswitch=3,
   dft='{{GFUN}}'
 /
 &inputp
   lpaw=.true.,
   pseudotype=3,
   file_pseudopw='Mn.{{FCT}}-spn-kjpaw_psl.0.3.1.UPF',
   author='ADC',
   lloc=-1,
   rcloc=1.9,
   which_augfun='PSQ',
   rmatch_augfun=1.3,
   nlcc=.true.,
   new_core_ps=.true.,
   rcore=0.7,
   tm=.true.
 /
6
3S  1  0  2.00  0.00  1.10  1.70  0.0
4S  2  0  2.00  0.00  0.80  1.60  0.0
3P  2  1  6.00  0.00  1.40  1.90  0.0
4P  3  1  0.00  0.40  1.40  1.90  0.0
3D  3  2  5.00  0.00  1.40  1.60  0.0
3D  3  2 -2.00 -0.30  1.40  1.60  0.0
