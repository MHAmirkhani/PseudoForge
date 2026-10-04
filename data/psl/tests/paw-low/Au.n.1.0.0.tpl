 &input
   title='Au',
   zed=79.,
   rel={{NREL}},
   config='[Xe] 4f14 5d10.0 6s1.0 6p0.0',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Au.{{FCT}}-n-kjpaw_psl.1.0.0.UPF',
   nconf=5
   frozen_core={{FROZEN_CORE}},
   configts(1)='5d10. 6s1 6p0',
   configts(2)='5d10. 6s0 6p0.5',
   configts(3)='5d10. 6s0 6p0',
   configts(4)='5d9.5 6s1 ',
   configts(5)='5d9.5 6s1 6p0',
 /
