 &input
   title='Se',
   zed=34.,
   rel={{NREL}},
   config='[Ar] 3d10.0 4s2.0 4p4.0 4d-2.0',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Se.{{FCT}}-n-rrkjus_psl.1.0.0.UPF',
   nconf=5,
   frozen_core={{FROZEN_CORE}},
   configts(1)='4s2 4p4'
   configts(2)='4s2 4p3'
   configts(3)='4s1 4p5'
   configts(4)='4s1 4p4'
   configts(5)='4s2 4p2'
 /
