#!/bin/bash
set -e

export GOPATH="$HOME/go"
export PATH="$GOPATH/bin:$HOME/.local/bin:$PATH"
mkdir -p $HOME/nfltools

# libdev buat pcap
sudo apt-get install libpcap-dev

# List tools dan repo/source
declare -A TOOLS_SOURCES=(
    [subzy]="go install -v github.com/PentestPad/subzy@latest"
    [naabu]="go install -v github.com/projectdiscovery/naabu/v2/cmd/naabu@latest"
    [chaos]="go install -v github.com/projectdiscovery/chaos-client/cmd/chaos@latest"
    [subfinder]="go install -v github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest"
    [assetfinder]="go install -v github.com/tomnomnom/assetfinder@latest"
    [httpx]="go install -v github.com/projectdiscovery/httpx/cmd/httpx@latest"
    [nuclei]="go install -v github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest"
    [gau]="go install -v github.com/lc/gau/v2/cmd/gau@latest"
    [waybackurls]="go install -v github.com/tomnomnom/waybackurls@latest"
    [gf]="go install -v github.com/tomnomnom/gf@latest"
    [uro]="pipx install uro"
    [crtsh]="manual_crtsh"
    [linkfinder]="manual_linkfinder"
)

# Fungsi instalasi manual crtsh
manual_crtsh() {
    cd $HOME/nfltools
    git clone https://github.com/YashGoti/crtsh.py.git
    cd crtsh.py
    mv crtsh.py crtsh
    chmod +x crtsh
    cp crtsh "$HOME/.local/bin/"
}

# Fungsi instalasi manual linkfinder
manual_linkfinder() {
    cd $HOME/nfltools
    git clone https://github.com/GerbenJavado/LinkFinder.git
    cd LinkFinder
    python3 setup.py install
    pip3 install -r requirements.txt --break-system-packages
    sed -i '1s|^#!/usr/bin/env python$|#!/usr/bin/env python3|' linkfinder.py
    ln -s "$HOME/nfltools/LinkFinder/linkfinder.py" "$HOME/.local/bin/linkfinder"
}

# Step 1: Cek tools
echo "🔎 Mengecek tools yang sudah ada di PATH ..."
missing_tools=()

for tool in "${!TOOLS_SOURCES[@]}"; do
    if command -v "$tool" >/dev/null 2>&1; then
        echo "✅ $tool sudah ada"
    else
        echo "❌ $tool BELUM ADA"
        missing_tools+=("$tool")
    fi
done

if [[ ${#missing_tools[@]} -eq 0 ]]; then
    echo "🎉 Semua tools sudah terinstall!"
    exit 0
fi

# Tampilkan summary dan tanya ke user
echo ""
echo "⚠️  Tools berikut BELUM ADA:"
for tool in "${missing_tools[@]}"; do
    echo "  - $tool"
done

read -p "➡️  Apakah ingin menginstall tools yang belum ada? (y/n): " jawab

if [[ "$jawab" != "y" ]]; then
    echo "🚫 Install dibatalkan. Tidak ada perubahan dilakukan."
    exit 0
fi

# Step 2: Install tools yang belum ada
echo ""
echo "🚀 Mulai menginstall tools yang belum ada ..."
for tool in "${missing_tools[@]}"; do
    install_cmd=${TOOLS_SOURCES[$tool]}
    if [[ "$install_cmd" == manual_crtsh ]]; then
        echo "🔨 Menginstall crtsh secara manual..."
        manual_crtsh
    elif [[ "$install_cmd" == manual_linkfinder ]]; then
        echo "🔨 Menginstall linkfinder secara manual..."
        manual_linkfinder
    else
        echo "🔨 Menjalankan: $install_cmd"
        eval "$install_cmd"
    fi
done

echo ""
echo "✅ Instalasi selesai. Silakan cek kembali dengan menjalankan script ini lagi."
