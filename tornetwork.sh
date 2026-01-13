#!/bin/bash

[[ "$UID" -ne 0 ]] && {
    echo "[!] Bu script ROOT olarak çalıştırılmalı."
    exit 1
}

LOGFILE="/var/log/tor_ipdegisim.log"

install_packages() {
    local distro
    distro=$(awk -F= '/^NAME/{print $2}' /etc/os-release | tr -d '"')

    case "$distro" in
        *"Ubuntu"* | *"Debian"*)
            apt-get update -y
            apt-get install -y curl tor
            ;;
        *"Fedora"* | *"CentOS"* | *"Red Hat"* | *"Amazon Linux"*)
            yum update -y
            yum install -y curl tor
            ;;
        *"Arch"*)
            pacman -S --noconfirm curl tor
            ;;
        *)
            echo "[x] Desteklenmeyen dağıtım: $distro"
            exit 1
            ;;
    esac
}

if ! command -v tor &>/dev/null || ! command -v curl &>/dev/null; then
    echo "[+] Gerekli paketler yükleniyor..."
    install_packages
fi

if ! systemctl --quiet is-active tor.service; then
    echo "[+] Tor servisi başlatılıyor..."
    systemctl start tor.service
fi

get_ip() {
    local ip
    for i in {1..5}; do
        ip=$(curl -s --max-time 10 -x socks5h://127.0.0.1:9050 https://checkip.amazonaws.com)
        [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && echo "$ip" && return
        sleep 2
    done
    echo ""
}

change_ip() {
    echo "[*] Yeni devre isteniyor..."
    systemctl reload tor.service
    sleep 5

    local new_ip=$(get_ip)

    if [[ -z "$new_ip" ]]; then
        echo "[!] IP alınamadı. NEWNYM zorlanıyor..."
        echo -e "AUTHENTICATE \"\"\r\nSIGNAL NEWNYM\r\nQUIT" | nc 127.0.0.1 9051 >/dev/null 2>&1
        sleep 5
        new_ip=$(get_ip)
    fi

    echo -e "\033[36m[+] Yeni Tor IP: $new_ip\033[0m"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $new_ip" >> "$LOGFILE"
}

clear
cat << "EOF"
████████╗ ██████╗ ██████╗     ██╗
╚══██╔══╝██╔═══██╗██╔══██╗    ██║
   ██║   ██║   ██║██████╔╝    ██║
   ██║   ██║   ██║██╔══██╗██  ██║
   ██║   ╚██████╔╝██║  ██║╚█████║
   ╚═╝    ╚═════╝ ╚═╝  ╚═╝ ╚════╝ 
     T O R   A N O N I M   R O T A R
EOF

while true; do
    read -rp "[?] IP değişim aralığı (saniye, minimum 10): " interval
    read -rp "[?] Kaç kez değişsin? (0 = sonsuz): " times

    [[ ! $interval =~ ^[0-9]+$ ]] && { echo "[x] Hatalı değer."; continue; }
    [[ ! $times =~ ^[0-9]+$ ]] && { echo "[x] Hatalı değer."; continue; }

    (( interval < 10 )) && interval=10

    if [[ $times -eq 0 ]]; then
        echo "[∞] Sonsuz IP değişimi başlatıldı..."
        while true; do
            change_ip
            sleep $interval
        done
    else
        for ((i=1; i<=times; i++)); do
            change_ip
            sleep $interval
        done
    fi
done
