 &input
   title='Al',
   zed=13.0,
   rel={{NREL}},
   config='[Ne] 3s2 3p1 3d-2.0 4f-2.0',
   iswitch=3,
   dft='{{GFUN}}'
 /
 &inputp
   pseudotype=2,
   file_pseudopw='Al.{{FCT}}-n-nc.UPF',
   author='TM',
   lloc=2,
   nlcc=.true.,
   tm=.true.
 /
3
3S  1  0  2.00  0.00  2.60  2.60  0.0
3P  2  1  1.00  0.00  2.60  2.60  0.0
3D  3  2  0.00  0.10  2.60  2.60  0.0
