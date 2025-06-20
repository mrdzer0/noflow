#!/bin/bash
export PATH="$PATH:$HOME/go/bin:$HOME/.local/bin"
set -e

usage() {
  echo "Usage: $0 -d <domain>"
  exit 1
}

# ----------- CHECK DEPENDENCIES -----------
check_tool() {
  if ! command -v "$1" &>/dev/null; then
    echo "[!] Required tool not found: $1"
    exit 1
  fi
}
REQUIRED_TOOLS=(subzy httpx gf)
for tool in "${REQUIRED_TOOLS[@]}"; do
  check_tool "$tool"
done

start_time=$(date +%s)
# ========================== FUNCTION BLOCK ==========================
find_and_check_jsfile() {
  local outdir="$1"
  local allurl_clean="$outdir/allurl_uniq.txt"
  local filtered_dir="$outdir/filtered"

  local JS_RAW="$filtered_dir/jslink_raw.txt"
  local JS_LIVE="$filtered_dir/jslink_live.txt"

  # Cari semua .js dari allurl, unique
  grep -i '\.js$' "$allurl_clean" | sort -u > "$JS_RAW"
  echo "[*] Ditemukan $(wc -l < "$JS_RAW") JS file dari allurl_uniq.txt"

  # Cek mana yang live dengan httpx + regex [2xx] / [3xx]
  if [ -s "$JS_RAW" ]; then
    httpx -l "$JS_RAW" -nc -silent -status-code \
    | grep -E '\[2[0-9]{2}\]|\[3[0-9]{2}\]' \
    | awk '{print $1}' | sort -u > "$JS_LIVE"
    echo "[*] JS live (status 2xx/3xx): $(wc -l < "$JS_LIVE")"
  else
    > "$JS_LIVE"
    echo "[!] Tidak ada JS file untuk dicek."
  fi
}

subzy_takeover() {
    outdir="$1"
    input="$outdir/subdomain.txt"
    rawout="$outdir/subzy-raw.txt"
    cleanout="$outdir/subzy-raw-clean.txt"
    jsonout="$outdir/subzy-vuln.json"

    echo "[*] Running subzy takeover check on $input ..."
    subzy run --targets "$input" --verify_ssl --hide_fails > "$rawout"

    echo "[*] Removing ANSI color codes from subzy output ..."
    sed -r 's/\x1b\[[0-9;]*m//g' "$rawout" > "$cleanout"

    echo "[*] Parsing only VULNERABLE results and converting to JSON ..."
    awk '
    /^\[ VULNERABLE/ {
        sub(/.*\]  -  /,"")
        split($0,a,"  \\[ ")
        subdomain=a[1]
        provider=substr(a[2],1,length(a[2])-1)
        getline; getline
        match($0, /\(https[^)]*\)/, arr); discussion=arr[0]
        gsub(/[\(\)]/,"",discussion)
        getline
        match($0, /\(https[^)]*\)/, arr2); documentation=arr2[0]
        gsub(/[\(\)]/,"",documentation)
        printf("{\"subdomain\":\"%s\",\"provider\":\"%s\",\"discussion_url\":\"%s\",\"documentation_url\":\"%s\"}\n", subdomain, provider, discussion, documentation)
    }
    ' "$cleanout" > "$jsonout"

    vuln_count=$(wc -l < "$jsonout")
    echo "[+] Done. $vuln_count potentially VULNERABLE subdomains saved to $jsonout"
}

filter_highvalue_links() {
  local outdir="$1"
  local subdomain_file="$outdir/subdomain.txt"
  local highvalue_sub="$outdir/subdomain_value.txt"
  local allurl_clean="$outdir/allurl_uniq.txt"
  local filtered_dir="$outdir/filtered"

  echo "[*] Filtering high-value subdomains..."
  grep -iE 'admin|api|internal|partner|dashboard|mobile|payment|dev|staging|beta|test|account|sso|auth|user|manage|proxy|jenkins|uat|stage|devops|staff|qa|console|portal' "$subdomain_file" > "$highvalue_sub"
  cat "$highvalue_sub" | sed 's|https\?://||;s|:.*||;s|/.*||' | sort -u > "$highvalue_sub.uniq"
  if [ ! -s "$highvalue_sub" ]; then
      echo "[!] Tidak ada high-value subdomain ditemukan, skip step ini"
      > "$filtered_dir/highvalue_links.txt"
  else
      grep -Fif "$highvalue_sub.uniq" "$allurl_clean" > "$filtered_dir/highvalue_links.txt" || true
      found=$(wc -l < "$filtered_dir/highvalue_links.txt")
      echo "[*] High-value links found: $found"
  fi
}

filter_endpoint_pattern() {
  local outdir="$1"
  local allurl_clean="$outdir/allurl_uniq.txt"
  local filtered_dir="$outdir/filtered"

  echo "[*] Endpoint pattern detection..."
  grep -iE '/(admin|dashboard|manage|console|internal|dev|setup|api|v1|v2|graphql|user|auth|config|debug|upload|download|backup|export|import|private|report|logs|swagger|doc|secret|archive|payment|account|test|staging|beta)[/?]' "$allurl_clean" > "$filtered_dir/endpoint_pattern_links.txt" || true
  tot_pattern=$(wc -l < "$filtered_dir/endpoint_pattern_links.txt")
  echo "[*] Endpoint pattern found: $tot_pattern"
}

gf_pattern_filtering() {
  local outdir="$1"
  local allurl_clean="$outdir/allurl_uniq.txt"
  local gf_dir="$outdir/gf_result"
  local GF_JSON_OUT="$gf_dir/gf_output.json"

  > "$GF_JSON_OUT"  # kosongkan file di awal

  echo "[*] GF filtering for common vuln patterns..."

  for pattern in sqli xss lfi ssrf idor redirect rce img-traversal interestingEXT interestingparams jsvar; do
    cat "$allurl_clean" | gf $pattern > "$gf_dir/${pattern}_links.txt"
    # Jika hasil tidak kosong, buat JSON-nya
    if [ -s "$gf_dir/${pattern}_links.txt" ]; then
      while read url; do
        if [ -n "$url" ]; then
          echo "{\"pattern\":\"$pattern\", \"url\":\"$url\"}" >> "$GF_JSON_OUT"
        fi
      done < "$gf_dir/${pattern}_links.txt"
    fi
  done
}

filter_httpx_response() {
  local outdir="$1"
  local allurl_clean="$outdir/allurl_uniq.txt"
  local filtered_dir="$outdir/filtered"

  local JSON_OUT="$filtered_dir/httpx_filtered.json"
  local TXT_OUT="$filtered_dir/httpx_filtered.txt_temp"

  > "$JSON_OUT"
  > "$TXT_OUT"

  echo "[*] Filtering by httpx response (status, headers, content)..."
  httpx -l "$allurl_clean" -nc -threads 100 -title -status-code -web-server -content-length -location -server -tech-detect -silent -o "$filtered_dir/httpx_result.txt"

  awk -v json="$JSON_OUT" -v txt="$TXT_OUT" '
  {
    url = $1
    status = gensub(/\[([0-9]{3})\]/, "\\1", "g", $2)
    content_length = gensub(/\[([0-9]+)\]/, "\\1", "g", $4)
    if (status ~ /^(200|301|302|303|401|403|500)$/ && content_length > 50) {
      printf("{\"status\":\"%s\", \"url\":%s}\n", status, url) >> json
      print url >> txt
    }
  }' "$filtered_dir/httpx_result.txt"

  # Dedup txt output
  sort -u "$TXT_OUT" -o "$TXT_OUT"

  echo "[*] Done. Output: $JSON_OUT ($(wc -l < "$JSON_OUT") JSON rows), $TXT_OUT ($(wc -l < "$TXT_OUT") unique URLs)"
}


filter_httpx_keywords() {
  local outdir="$1"
  local filtered_dir="$outdir/filtered"
  local KEYWORDS="Set-Cookie|Authorization|Token|Api-Key|isAdmin|admin|debug|role|secret|bearer|password|flag"
  local IN="$filtered_dir/httpx_result.txt"
  local JSON_OUT="$filtered_dir/httpx_keywords.json"
  local TXT_OUT="$filtered_dir/httpx_keywords.txt_temp"

  > "$JSON_OUT"
  > "$TXT_OUT"

  if [ -s "$IN" ]; then
    grep -ioE "$KEYWORDS" "$IN" | sort -u | while read keyword; do
      if [ -n "$keyword" ]; then
        grep -i "$keyword" "$IN" | while read line; do
          url=$(echo "$line" | cut -d' ' -f1)
          if [ -n "$url" ]; then
            echo "{\"keyword\":\"$keyword\", \"url\":\"$url\"}" >> "$JSON_OUT"
            echo "$url" >> "$TXT_OUT"
          fi
        done
      fi
    done
    sort -u "$TXT_OUT" -o "$TXT_OUT"
  fi

  echo "[*] Done. Output: $JSON_OUT ($(wc -l < "$JSON_OUT") JSON rows), $TXT_OUT ($(wc -l < "$TXT_OUT") unique URLs)"
}

merge_and_dedup_final() {
  local outdir="$1"
  local filtered_dir="$outdir/filtered"
  local gf_dir="$outdir/gf_result"
  local FINAL_OUT="$outdir/all_final_filtered.txt"

  echo "[*] Merging and final deduplication..."
  cat \
    "$filtered_dir/highvalue_links.txt" \
    "$filtered_dir/endpoint_pattern_links.txt" \
    "$filtered_dir/httpx_filtered.txt_temp" \
    "$filtered_dir/httpx_keywords.txt_temp" \
    $gf_dir/*_links.txt \
    | uro | sort -u > "$FINAL_OUT"
  
  httpx -l "$FINAL_OUT" -nc -threads 100 -title -status-code -web-server -content-length -location -server -tech-detect -silent -o "$outdir/all_final_filtered_httpx.txt"
  echo "[+] Done! Output in $FINAL_OUT (hasil siap untuk manual review / eksploitasi lanjut)"
}

write_summary_json() {
  local outdir="$1"
  local filtered_dir="$outdir/filtered"
  local gf_dir="$outdir/gf_result"
  local summary_file="$outdir/step3.json"
  local start_time="$2"
  local end_time=$(date +%s)
  local elapsed_sec=$((end_time - start_time))

  # Format elapsed time as 0h 0m 0s
  local h=$((elapsed_sec/3600))
  local m=$(((elapsed_sec%3600)/60))
  local s=$((elapsed_sec%60))
  local elapsed_formatted="${h}h ${m}m ${s}s"

  # Count line numbers
  local link_interesting=$(wc -l < "$filtered_dir/highvalue_links.txt")
  local link_endpoint=$(wc -l < "$filtered_dir/endpoint_pattern_links.txt")
  local httpx_response=$(wc -l < "$filtered_dir/httpx_filtered.txt_temp")
  local httpx_keyword=$(wc -l < "$filtered_dir/httpx_keywords.txt_temp")
  local jslink=$(wc -l < "$filtered_dir/jslink_live.txt")
  local takeover=$(wc -l < "$outdir/subzy-vuln.json")

  # GF pattern non-empty
  local gf_list="["
  local first=1
  for file in "$gf_dir"/*_links.txt; do
    [ ! -s "$file" ] && continue
    pattern=$(basename "$file" | sed 's/_links.txt//')
    count=$(wc -l < "$file")
    if [ $first -eq 0 ]; then gf_list+=", "; fi
    gf_list+="{\"pattern\":\"$pattern\", \"count\":$count}"
    first=0
  done
  gf_list+="]"

  # Write JSON summary
  cat <<EOF > "$summary_file"
{
  "jslink": $jslink,
  "takeover": $takeover,
  "link_interesting": $link_interesting,
  "link_endpoint": $link_endpoint,
  "httpx_response": $httpx_response,
  "httpx_keyword": $httpx_keyword,
  "gf": $gf_list,
  "elapsed_time": "$elapsed_formatted"
}
EOF

  echo "[*] Summary written to $summary_file"
}

# ========================== MAIN SCRIPT ==========================

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
mkdir -p "$outdir/filtered" "$outdir/gf_result"

subzy_takeover "$outdir"
find_and_check_jsfile "$outdir"
filter_highvalue_links "$outdir"
filter_endpoint_pattern "$outdir"
gf_pattern_filtering "$outdir"
filter_httpx_response "$outdir"
filter_httpx_keywords "$outdir"
merge_and_dedup_final "$outdir"

write_summary_json "$outdir" "$start_time"
# Bersihkan file temporary
rm -f "$outdir/filtered/"*_temp
rm -f "$outdir/subdomain_value.txt"
rm -f "$outdir/subdomain_value.txt.uniq"
rm -f "$outdir/subzy-raw.txt"
rm -f "$outdir/subzy-raw-clean.txt"
echo "[*] Semua proses selesai. Output sudah bersih!"
