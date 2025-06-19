#!/bin/bash

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

# ----------- Load .env if exists -----------
if [[ -f ".env" ]]; then
  set -o allexport
  source .env
  set +o allexport
fi

if [[ -z "$domain" ]]; then
  usage
fi

# Variable declaration
outdir="output/$domain"
output_subdomain="$outdir/subdomain.txt"
mkdir -p "$outdir"
mkdir -p "$outdir/raw"
SECONDS=0

format_time() {
  local T=$1
  local H=$((T/3600))
  local M=$(( (T%3600)/60 ))
  local S=$((T%60))
  printf "%dh %dm %ds" $H $M $S
}

run_subfinder() {
  echo "[*] Running subfinder..."
  subfinder -d "$domain" -all -o "$outdir/subfinder.txt"
}

run_assetfinder() {
  echo "[*] Running assetfinder..."
  assetfinder "$domain" | tee "$outdir/assetfinder.txt"
}

run_chaos_dump() {
  echo "[*] Running Chaos Dump (ProjectDiscovery)..."
  local chaos_index="$outdir/chaos_index.json"
  curl -s "https://chaos-data.projectdiscovery.io/index.json" -o "$chaos_index"
  local chaos_url=$(grep -w "$domain" "$chaos_index" | grep "URL" | sed 's/\"URL\": \"//;s/\",//' | xargs || true)
  if [[ -n "$chaos_url" ]]; then
    (cd "$outdir" && curl -sSL "$chaos_url" -O && unzip -qq '*.zip' && cat ./*.txt > chaos.txt && rm -f *.zip ./*.txt)
    echo "[+] Chaos Dump: ditemukan dan digabung di chaos.txt"
  else
    echo "[-] Chaos Dump: Tidak ditemukan untuk domain ini"
  fi
  rm -f "$chaos_index"
}

run_chaos_cli() {
  echo "[*] Running Chaos CLI..."
  chaos -d "$domain" -silent -o "$outdir/chaos2.txt"
}

run_crtsh() {
  echo "[*] Running crtsh..."
  crtsh -d "$domain" -r | tee "$outdir/crtsh.txt"
}

merge_and_clean() {
  echo "[*] Menggabungkan dan membersihkan hasil..."
  # Merge semua file txt (kecuali subdomain.txt) menjadi satu
  find "$outdir" -maxdepth 1 -type f -name '*.txt' ! -name 'subdomain.txt' -exec cat {} + | sort -u > "$output_subdomain"
  echo "[*] Hasil akhir di $output_subdomain"

  # Hapus hasil dari masing-masing tools, kecuali subdomain.txt
  find "$outdir" -maxdepth 1 -type f -name '*.txt' ! -name 'subdomain.txt' -exec rm -f {} +
}

run_dnsx() { 
  local raw_dnsx="$outdir/raw/dnsx_raw.json"
  local final_dnsx="$outdir/dnsx.json"
  echo "[*] Running dnsx..."
  dnsx -l "$output_subdomain" -a -cname -resp -ns -mx -txt -aaaa -json -silent -o "$raw_dnsx"

  echo "[*] dnsx result saved to $final_dnsx"
}

run_httpx() {
  local merged_httpx="$outdir/httpx_combined.txt"
#   local ports="80,81,82,83,84,85,88,443,444,3000,3001,3002,4000,4433,4443,5000,5001,5002,5800,5801,5802,5900,5984,5985,7000,7001,7002,7070,7474,7777,8000,8001,8008,8009,8010,8080,8081,8082,8085,8088,8089,8090,8091,8222,8333,8443,8444,8500,8501,8765,8800,8880,8888,9000,9001,9002,9040,9043,9080,9090,9091,9100,9200,9300,9443,9444,9800,9990,9999,10000,10443,10444,12443,16080,18091,18092,20000,20720,27017,28017,30000,3128,5601,6443,16080,18091,18092,45001,49152,49153,49154,49155,49156,49157"
  local ports="80,8080"

  echo "[*] Running httpx..."
  httpx -l "$outdir/subdomain.txt" -silent -fr -json -o "$outdir/raw/httpx.json"
  httpx -l "$outdir/subdomain.txt" -p $ports -silent -fr -json -o "$outdir/raw/httpx_port.json"

  jq -r '.url' "$outdir/raw/httpx.json" "$outdir/raw/httpx_port.json" | sort -u > "$merged_httpx"
}


# Main
run_subfinder
run_assetfinder
run_chaos_dump
run_chaos_cli
run_crtsh
merge_and_clean
run_dnsx
run_httpx


total_subdomain=$(wc -l < "$outdir/subdomain.txt" 2>/dev/null || echo 0)
total_httpx=$(wc -l < "$outdir/httpx_combined.txt" 2>/dev/null || echo 0)
elapsed_time=$(format_time $SECONDS)

cat <<EOF > "$outdir/step1.json"
{
  "total_subdomain": $total_subdomain,
  "httpx": $total_httpx,
  "elapsed_time": "$elapsed_time"
}
EOF

echo "[*] Summary saved at $outdir/step1.json"
echo "[*] DONE. Output tersimpan di $outdir/"


