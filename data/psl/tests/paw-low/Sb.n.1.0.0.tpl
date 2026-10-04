 &input
   title='Sb',
   zed=51.,
   rel={{NREL}},
   config='[Kr] 4d10.0 5s2.0 5p3.0 5d-2.0',
   iswitch=2,
 /
 &test
   file_pseudo='{{PSDIR}}/Sb.{{FCT}}-n-kjpaw_psl.1.0.0.UPF',
   nconf=5
   frozen_core={{FROZEN_CORE}},
   configts(1)='5s2 5p3'
   configts(2)='5s2 5p2 5d0'
   configts(3)='5s2 5p2 5d0.5'
   configts(4)='5s1 5p3 5d0'
   configts(5)='5s1 5p3 5d0.5'
 /
