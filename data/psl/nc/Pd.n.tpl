 &input
   title='Pd',
   zed=46.0,
   rel={{NREL}},
   config='[Kr] 4d10.0 5s0 5p0',
   iswitch=3,
   dft='{{GFUN}}'
 /
 &inputp
   pseudotype=2,
   file_pseudopw='Pd.{{FCT}}-n-nc.UPF',
   author='TM',
   lloc=0,
   nlcc=.true.,
   tm=.true.
 /
3
5P  2  1  0.00  0.00  2.60  2.60  0.0
4D  3  2 10.00  0.00  2.45  2.45  0.0
5S  1  0  0.00  0.00  2.45  2.45  0.0
