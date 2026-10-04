 &input
   title='Ru b',
   zed=44.,
   rel={{NREL}},
   config='[Kr] 4d6.0 5s2.0 5p0.0',
   iswitch=3,
   dft='{{GFUN}}'
 /
 &inputp
   pseudotype=3,
   file_pseudopw='Ru.{{FCT}}-spn-rrkjus_psl.0.3.0.UPF',
   author='ADC',
   lloc=-1,
   rcloc=1.4,
   which_augfun='PSQ',
   rmatch_augfun_nc=.true.,
   nlcc=.true.,
   new_core_ps=.true.,
   rcore=0.9,
   tm=.true.
 /
6
4S  1  0  2.00  0.00  0.75  1.70  0.0
5S  2  0  2.00  0.00  0.75  1.30  0.0
4P  2  1  6.00  0.00  0.75  1.80  0.0
5P  3  1  0.00  0.00  0.75  1.30  0.0
4D  3  2  6.00  0.00  1.00  1.80  0.0
4D  3  2 -2.00  0.30  1.00  1.80  0.0
