 &input
   title='V b',
   zed=23.0,
   rel={{NREL}},
   config='[Ar] 3d3.0 4s2 4p0',
   iswitch=3,
   dft='{{GFUN}}'
 /
 &inputp
   pseudotype=3,
   file_pseudopw='V.{{FCT}}-spn-rrkjus_psl.0.2.3.UPF',
   author='ADC',
   lloc=-1,
   rcloc=2.0,
   which_augfun='PSQ',
   rmatch_augfun=0.7,
   nlcc=.true.,
   new_core_ps=.true.,
   rcore=0.7,
   tm=.true.
 /
6
3S  1  0  2.00  0.00  1.10  1.50  0.0
4S  2  0  2.00  0.00  1.10  1.50  0.0
3P  2  1  6.00  0.00  1.40  1.50  0.0
4P  3  1  0.00  3.30  0.90  1.80  0.0
3D  3  2  3.00  0.00  1.40  1.70  0.0
3D  3  2 -2.00  0.30  1.40  1.70  0.0
