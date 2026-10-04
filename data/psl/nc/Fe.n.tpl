 &input
   title='Fe',
   zed=26.,
   rel={{NREL}},
   config='[Ar] 4s2.0 3d6. 4p0',
   iswitch=3,
   dft='{{GFUN}}'
 /
 &inputp
   pseudotype=2,
   file_pseudopw='Fe.{{FCT}}-n-nc.UPF',
   author='TM',
   lloc=0,
   nlcc=.true.,
   tm=.true.
 /
3
4P  2  1  0.00  0.00  2.40  2.40  0.0
3D  3  2  6.00  0.00  2.20  2.20  0.0
4S  1  0  2.00  0.00  2.20  2.20  0.0
