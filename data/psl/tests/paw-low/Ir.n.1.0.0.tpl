 &input
   title='Ir',
   zed=77.,
   rel={{NREL}},
   config='[Xe] 4f14.0 5d7.0 6s2.0 6p0.0',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Ir.{{FCT}}-n-kjpaw_psl.1.0.0.UPF',
   nconf=5,
   frozen_core={{FROZEN_CORE}},
   configts(1)='6s2 6p0 5d7'
   configts(2)='6s1.5 6p0 5d7'
   configts(3)='6s1.5 6p0.3 5d7'
   configts(4)='6s1.5 6p0.0 5d6.5'
   configts(5)='6s2 6p1.0 5d6'
 /
