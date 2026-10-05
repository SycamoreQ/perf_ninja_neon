// Scalar byte-sum loop: present ONLY in the -fno-vectorize build (the other two builds use udot instead)
// 4 input bytes per iteration, 4 independent accumulators
loop:
	ldurb	w0, [x17, #-3]
	add	w15, w15, w0
	ldurb	w0, [x17, #-2]
	add	w10, w10, w0
	ldurb	w0, [x17, #-1]
	add	w13, w13, w0
	ldrb	w0, [x17], #4
	add	w14, w14, w0
	add	x12, x12, #4
	cmp	x16, x12
	b.ne	loop
