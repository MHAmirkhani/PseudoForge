 &input
   title='Ge',
   zed=32.,
   rel={{NREL}},
   config='[Ar] 3d10.0 4s2.0 4p2.0 4d-1',
   iswitch=3,
   dft='{{GFUN}}'
 /
 &inputp
   pseudotype=2,
   file_pseudopw='Ge.{{FCT}}-n-nc.UPF',
   author='TM',
   lloc=2,
   nlcc=.true.,
   tm=.true.
 /
3
4S  1  0  2.00  0.00  2.10  2.10  0.0
4P  2  1  2.00  0.00  2.10  2.10  0.0
4D  3  2  0.00  0.10  2.40  2.40  0.0
