 &input
   title='Os q',
   zed=76.,
   rel={{NREL}},
   iswitch=3,
   config='[Xe] 4f14.0 5d6.0 6s2.0 6p0.0',
   dft='{{GFUN}}'
 /
 &inputp
   lloc=0,
   pseudotype=3,
   file_pseudopw='Os.{{FCT}}-n-rrkjus_psl.0.2.3.UPF',
   author='ADC',
   nlcc=.true.,
   rcore=0.9,
 /
4
6P  2  1  0.00  0.00  2.60  2.60  0.0
5D  3  2  6.00  0.00  1.90  2.30  0.0
5D  3  2  0.00 -0.20  1.90  2.30  0.0
6S  1  0  2.00  0.00  2.50  2.50  0.0
