#!/bin/sh
# Creates the whole llvm-mca suite: one directory per CPU model, each with its own run_mca.sh.
# usage: ./setup_mca_suite.sh [cpu ...]        (default: apple-m4 apple-m1 neoverse-v2 cortex-x4)
#        DEST=my_dir ./setup_mca_suite.sh      (default dest: ./mca_suite)
# Extra models later:  ./setup_mca_suite.sh neoverse-v1 neoverse-n1   (adds directories, keeps existing ones)
DEST=${DEST:-mca_suite}
CPUS=${*:-apple-m4 apple-m1 neoverse-v2 cortex-x4}
mkdir -p "$DEST/common/loops"

# ---------------------------------------------------------------- loop files (shared by all CPUs)
cat > "$DEST/common/loops/loop_neon.s" << 'LOOP_EOF'
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
LOOP_EOF

cat > "$DEST/common/loops/loop_plain.s" << 'LOOP_EOF'
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
LOOP_EOF

cat > "$DEST/common/loops/loop_udot.s" << 'LOOP_EOF'
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
LOOP_EOF

cat > "$DEST/common/loops/loop_scalar_sum.s" << 'LOOP_EOF'
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
LOOP_EOF

# ---------------------------------------------------------------- per-CPU run_mca.sh template (kept in common/run_mca.template)
TEMPLATE_FILE="$DEST/common/run_mca.template"
cat > "$TEMPLATE_FILE" << 'TPL_EOF'
#!/bin/sh
# Generated. CPU model is baked in below. More iterations:  ITER=5000 ./run_mca.sh
CPU=__CPU__
ITER=${ITER:-1000}
HERE=$(cd "$(dirname "$0")" && pwd)
LOOPS="$HERE/../common/loops"
OUT="$HERE/out"
mkdir -p "$OUT"
TSV="$OUT/summary.tsv"
printf "cpu\tloop\twidth\tcyc_per_iter\tunits\tmodel\tcyc_per_unit\n" > "$TSV"

# loop name -> units per iteration, unit, builds containing the loop
meta() {
  case $1 in
    loop_neon)       echo "8 outputs intrinsics" ;;
    loop_plain)      echo "1 outputs scalar+autovec" ;;
    loop_scalar_sum) echo "4 bytes scalar-only" ;;
    loop_udot)       echo "64 bytes autovec+intrinsics" ;;
  esac
}
fp_hash() { (shasum 2>/dev/null || sha1sum) | cut -c1-6; }

printf "%-12s %-16s %5s %9s %6s %-7s %10s  %s\n" cpu loop width cyc/iter units model cyc/unit "(unit, builds)"
for f in loop_neon loop_plain loop_scalar_sum loop_udot; do
  set -- $(meta "$f"); units=$1; per=$2; builds=$3
  src="$LOOPS/$f.s"; out="$OUT/$f.mca.txt"
  if [ ! -f "$src" ]; then
    printf "%-12s %-16s n/a (missing %s)\n" "$CPU" "$f" "$src"; continue
  fi
  if llvm-mca -mtriple=arm64-apple-macos -mcpu="$CPU" --iterations="$ITER" \
       --bottleneck-analysis --timeline --timeline-max-iterations=3 \
       "$src" > "$out" 2>&1; then
    cyc=$(awk '/^Total Cycles:/{print $3}' "$out")
    it=$(awk '/^Iterations:/{print $2}' "$out")
    w=$(awk '/^Dispatch Width:/{print $3}' "$out")
    fp=$(sed -n '/^Resources:/,/^$/p' "$out" | fp_hash)
    cpi=$(awk -v c="$cyc" -v i="$it" 'BEGIN{printf "%.2f", c/i}')
    cpu_=$(awk -v c="$cyc" -v i="$it" -v u="$units" 'BEGIN{printf "%.3f", c/i/u}')
    printf "%-12s %-16s %5s %9s %6s %-7s %10s  %s, %s\n" "$CPU" "$f" "$w" "$cpi" "$units" "$fp" "$cpu_" "$per" "$builds"
    printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "$CPU" "$f" "$w" "$cpi" "$units" "$fp" "$cpu_" >> "$TSV"
  else
    printf "%-12s %-16s FAILED, see %s\n" "$CPU" "$f" "$out"
  fi
done
TPL_EOF

for cpu in $CPUS; do
  mkdir -p "$DEST/$cpu"
  sed "s/__CPU__/$cpu/" "$TEMPLATE_FILE" > "$DEST/$cpu/run_mca.sh"
  chmod +x "$DEST/$cpu/run_mca.sh"
done

# ---------------------------------------------------------------- run_all.sh
cat > "$DEST/run_all.sh" << 'ALL_EOF'
#!/bin/sh
# Runs every CPU directory's run_mca.sh, then prints the predicted speedups per model.
ROOT=$(cd "$(dirname "$0")" && pwd)
ALL="$ROOT/all_summary.tsv"
: > "$ALL"
for d in "$ROOT"/*/; do
  name=$(basename "$d")
  [ "$name" = common ] && continue
  [ -f "$d/run_mca.sh" ] || continue
  echo "##### $name"
  sh "$d/run_mca.sh"
  [ -f "$d/out/summary.tsv" ] && tail -n +2 "$d/out/summary.tsv" >> "$ALL"
  echo
done
echo "##### predicted speedups (model cycles per unit of work)"
printf "%-12s %-24s %-24s\n" cpu "steady-state plain/NEON" "byte-sum scalar/udot"
awk -F'\t' '
  $2=="loop_plain"{p[$1]=$7} $2=="loop_neon"{n[$1]=$7}
  $2=="loop_scalar_sum"{s[$1]=$7} $2=="loop_udot"{u[$1]=$7}
  END{
    for (c in p) {
      a = ((c in n) && n[c] > 0) ? sprintf("%.2fx", p[c]/n[c]) : "n/a"
      b = ((c in s) && (c in u) && u[c] > 0) ? sprintf("%.1fx", s[c]/u[c]) : "n/a"
      printf "%-12s %-24s %-24s\n", c, a, b
    }
  }' "$ALL" | sort
echo
echo "Same 'model' hash across CPUs = same underlying LLVM scheduling model (not independent evidence)."
ALL_EOF
chmod +x "$DEST/run_all.sh"

echo "Created $DEST/ with: common/loops, run_all.sh, and a run_mca.sh in each of: $CPUS"
