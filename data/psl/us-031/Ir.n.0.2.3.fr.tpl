 &input
   title='Ir',
   zed=77.,
   rel={{NREL}},
   config='[Xe] 4f14.0 5d7.0 6s2.0 6p0.0',
   iswitch=3,
   dft='{{GFUN}}'
 /
 &inputp
   pseudotype=3,
   file_pseudopw='Ir.{{FCT}}-n-rrkjus_psl.0.2.3.UPF',
   author='ADC',
   lloc=-1,
   rcloc=2.3,
   which_augfun='PSQ',
   rmatch_augfun=1.0,
   nlcc=.true.,
   new_core_ps=.true.,
   rcore=1.6,
   tm=.true.
 /
6
6S  1  0  2.00  0.00  2.00  2.40  0.0
6S  1  0  0.00  2.50  2.00  2.40  0.0
6P  2  1  0.00  0.00  2.30  2.60  0.0
6P  2  1  0.00  3.50  2.30  2.60  0.0
5D  3  2  7.00  0.00  1.80  2.20  0.0
5D  3  2  0.00  0.80  1.80  2.20  0.0
