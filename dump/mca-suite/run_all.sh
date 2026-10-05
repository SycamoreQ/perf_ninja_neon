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
