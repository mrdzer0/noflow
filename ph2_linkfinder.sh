#!/bin/bash
export PATH="$PATH:$HOME/go/bin:$HOME/.local/bin"

set -e

usage() {
  echo "Usage: $0 -d <domain>"
  exit 1
}

# Parse argumen
while getopts "d:" opt; do
  case $opt in
    d) domain="$OPTARG" ;;
    *) usage ;;
  esac
done

if [[ -z "$domain" ]]; then
  usage
fi

outdir="output/$domain"
INPUT="$outdir/subdomain.txt"
Probinginput="$outdir/httpx_combined.txt"

KATANA_OUT="$outdir/links_katana.txt"
GAU_OUT="$outdir/links_gau.txt"
WAYBACK_OUT="$outdir/links_waybackurls.txt"
ALL_LINKS="$outdir/raw/all_links.txt"
ALLURL_CLEAN="$outdir/allurl_uniq.txt"
SECONDS=0

# ----------- CHECK DEPENDENCIES -----------
check_tool() {
  if ! command -v "$1" &>/dev/null; then
    echo "[!] Required tool not found: $1"
    exit 1
  fi
}
REQUIRED_TOOLS=(katana gau waybackurls uro)
for tool in "${REQUIRED_TOOLS[@]}"; do
  check_tool "$tool"
done

format_time() {
  local T=$1
  local H=$((T/3600))
  local M=$(( (T%3600)/60 ))
  local S=$((T%60))
  printf "%dh %dm %ds" $H $M $S
}

echo "[*] Running katana..."
cat "$Probinginput" | katana -silent -jc -o "$KATANA_OUT"

echo "[*] Running gau..."
cat "$INPUT" | gau --providers wayback,commoncrawl,urlscan,otx --threads 50 | tee "$GAU_OUT"

echo "[*] Running waybackurls..."
cat "$INPUT" | waybackurls | tee "$WAYBACK_OUT"

echo "[*] Merging & sorting links..."
cat "$KATANA_OUT" "$GAU_OUT" "$WAYBACK_OUT" | sort -u > "$ALL_LINKS"

echo "[*] Deduplicate links using uro..."
cat "$ALL_LINKS" | uro > "$ALLURL_CLEAN"

out_katana=$(wc -l < "$KATANA_OUT" 2>/dev/null || echo 0)
out_gau=$(wc -l < "$GAU_OUT" 2>/dev/null || echo 0)
out_wayback=$(wc -l < "$WAYBACK_OUT" 2>/dev/null || echo 0)
out_total=$(wc -l < "$ALL_LINKS" 2>/dev/null || echo 0)
out_clear=$(wc -l < "$ALLURL_CLEAN" 2>/dev/null || echo 0)
elapsed_time=$(format_time $SECONDS)

cat <<EOF > "$outdir/step2.json"
{
  "katana": $out_katana,
  "gau": $out_gau,
  "waybackurl": $out_wayback,
  "total": $out_total,
  "dedup_url": $out_clear,
  "elapsed_time": "$elapsed_time"
}
EOF

rm "$outdir"/links_*.txt

echo "[*] Summary saved at $outdir/step2.json"
echo "[*] DONE. Output tersimpan di $outdir/"