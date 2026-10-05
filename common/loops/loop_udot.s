// udot byte-sum loop: present in the auto-vectorized AND the intrinsics builds
// 64 input bytes per iteration
loop:
	ldp	q5, q6, [x9, #-32]
	ldp	q7, q16, [x9], #64
	udot.4s	v0, v5, v1
	udot.4s	v2, v6, v1
	udot.4s	v3, v7, v1
	udot.4s	v4, v16, v1
	subs	x13, x13, #64
	b.ne	loop
