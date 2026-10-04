 &input
   title='Cr c',
   zed=24.0,
   rel={{NREL}},
   config='[Ar] 3d5.0 4s1 4p0',
   iswitch=3,
   dft='{{GFUN}}'
 /
 &inputp
   pseudotype=3,
   file_pseudopw='Cr.{{FCT}}-spn-rrkjus_psl.0.2.3.UPF',
   author='ADC',
   lloc=-1,
   rcloc=2.0,
   which_augfun='PSQ',
   rmatch_augfun=1.3,
   nlcc=.true.,
   new_core_ps=.true.,
   rcore=0.7, 
   tm=.true.
 /
6
3S  1  0  2.00  0.00  1.00  1.50  0.0
4S  2  0  1.00  0.00  1.00  1.50  0.0
3P  2  1  6.00  0.00  1.40  1.50  0.0
4P  3  1  0.00  3.10  0.90  1.70  0.0
3D  3  2  5.00  0.00  1.30  1.70  0.0
3D  3  2 -2.00  0.30  1.30  1.70  0.0
