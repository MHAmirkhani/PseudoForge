 &input
   title='Hg',
   zed=80.,
   rel={{NREL}},
   config='[Xe] 4f14 5d10.0 6s2.0 6p0.0',
   iswitch=3,
   dft='{{GFUN}}'
 /
 &inputp
   pseudotype=2,
   file_pseudopw='Hg.{{FCT}}-n-nc.UPF',
   author='TM',
   lloc=0,
   nlcc=.true.,
   tm=.true.
 /
3
6P  2  1  0.00  0.00  2.70  2.70  0.0
5D  3  2 10.00  0.00  2.70  2.70  0.0
6S  1  0  2.00  0.00  2.70  2.70  0.0
