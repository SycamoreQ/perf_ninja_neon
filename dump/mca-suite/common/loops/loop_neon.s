// NEON steady-state loop (intrinsics build): 8 outputs per iteration
loop:
	ldr	d2, [x10, x16]
	ldr	d3, [x3, x16]
	usubl.8h	v2, v3, v2
	ext.16b	v3, v1, v2, #14
	add.8h	v2, v3, v2
	ext.16b	v3, v1, v2, #12
	add.8h	v2, v3, v2
	ext.16b	v3, v1, v2, #8
	add.8h	v0, v2, v0
	add.8h	v2, v0, v3
	str	q2, [x15], #16
	dup.8h	v0, v2[7]
	add	x16, x16, #8
	cmp	x16, x9
	b.lt	loop
