 &input
   title='Mn',
   zed=25.,
   rel={{NREL}},
   config='[Ar] 4s2.0 4p0.0 3d5.0',
   iswitch=3,
   dft='{{GFUN}}'
 /
 &inputp
   pseudotype=2,
   file_pseudopw='Mn.{{FCT}}-n-nc.UPF',
   author='TM modified by ADC',
   lloc=0,
   nlcc=.true.,
   tm=.true.
 /
3
4P  2  1  0.00  0.00  2.60  2.60  0.0
3D  3  2  5.00  0.00  2.35  2.35  0.0
4S  1  0  2.00  0.00  2.30  2.30  0.0
