// Plain C++ -O3 steady-state loop: identical in the scalar (-fno-vectorize) and auto-vectorized builds
// 1 output per iteration
loop:
	ldrb	w17, [x16, x14]
	ldrb	w0, [x13, x14]
	sub	w10, w10, w17
	add	w10, w10, w0
	strh	w10, [x15, x14, lsl #1]
	add	x14, x14, #1
	cmp	x14, x12
	b.lo	loop
