 &input
   title='Sr',
   zed=38.,
   rel={{NREL}},
   config='[Kr] 5s2.0 5p0.0 4d0.0',
   iswitch=3,
   dft='{{GFUN}}'
 /
 &inputp
   pseudotype=2,
   file_pseudopw='Sr.{{FCT}}-n-nc.UPF',
   author='TM',
   lloc=0,
   nlcc=.true.,
   tm=.true.
 /
3
5P  2  1  0.00  0.00  3.80  3.80  0.0
4D  3  2  0.00  0.00  3.60  3.60  0.0
5S  1  0  2.00  0.00  3.60  3.60  0.0
