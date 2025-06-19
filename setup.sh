#!/bin/bash

set -e  # Stop on error

echo "🚀 [1/8] Menyiapkan lingkungan Go & PATH..."

export GOPATH="/root/go"
export PATH="$GOPATH/bin:/root/.local/bin:$PATH"
mkdir -p "$GOPATH/bin"

echo "📦 [2/8] Menginstal dependency sistem..."
apt update && apt install -y libpcap-dev git curl wget unzip python3-pip pipx

echo "🧼 [3/8] Membersihkan folder hasil git clone sebelumnya..."
rm -rf /opt/crtsh.py /tmp/Gf-Patterns

echo "📥 [4/8] Instalasi tools Go..."

go install -v github.com/PentestPad/subzy@latest
go install -v github.com/projectdiscovery/naabu/v2/cmd/naabu@latest
go install -v github.com/projectdiscovery/chaos-client/cmd/chaos@latest
go install -v github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest
go install -v github.com/tomnomnom/assetfinder@latest
go install -v github.com/projectdiscovery/httpx/cmd/httpx@latest
go install -v github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest
go install -v github.com/lc/gau/v2/cmd/gau@latest
go install -v github.com/tomnomnom/waybackurls@latest
go install -v github.com/tomnomnom/gf@latest

echo "🐍 [5/8] Instalasi uro via pipx..."
pipx install --force uro

echo "📦 [6/8] Instalasi manual crtsh..."
cd /opt
git clone https://github.com/YashGoti/crtsh.py.git
cd crtsh.py
mv crtsh.py crtsh
chmod +x crtsh
cp crtsh /usr/bin/

echo "🧩 [7/8] Setup gf dan pattern-nya..."
mkdir -p ~/.gf
cp -r "$GOPATH/pkg/mod/github.com/tomnomnom/gf@"*/examples/* ~/.gf/
git clone https://github.com/1ndianl33t/Gf-Patterns /tmp/Gf-Patterns
cp /tmp/Gf-Patterns/*.json ~/.gf/

echo "✅ [8/8] Verifikasi semua tools di PATH..."

TOOLS=(subfinder assetfinder chaos httpx naabu nuclei gau waybackurls gf uro subzy crtsh)

for tool in "${TOOLS[@]}"; do
  if command -v "$tool" >/dev/null 2>&1; then
    echo "✅ $tool tersedia di PATH"
  else
    echo "❌ $tool TIDAK terdeteksi! Cek instalasi"
  fi
done

echo -e "\n📍 Final PATH environment: $PATH"
echo "✅ Semua tools berhasil diinstal dan siap dipakai di SSH/N8N."
