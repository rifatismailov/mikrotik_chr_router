#!/bin/bash
set -euo pipefail

# 🧾 Параметри конфігурації
SRC_IP="192.168.88.200"      # IP хоста, на який звертаються з LAN
DST_IP="172.21.0.2"          # IP MikroTik у Docker bridge
LAN_SUBNET="192.168.88.0/24" # LAN підмережа

# Порти для пробросу
TCP_PORTS=(8291)           # WinBox
UDP_PORTS=(51820 1701)     # WireGuard, L2TP

echo "🔎 Перевірка, що використовується iptables-nft…"
ALT="$(sudo update-alternatives --display iptables | sed -n 's/.*вказує на \(.*\)$/\1/p' | tr -d ' ')"
if [[ "$ALT" != "/usr/sbin/iptables-nft" ]]; then
  echo "❌ Зараз активний $ALT. Перемкни на nft і перезапусти Docker:"
  echo "    sudo update-alternatives --set iptables /usr/sbin/iptables-nft"
  echo "    sudo update-alternatives --set ip6tables /usr/sbin/ip6tables-nft"
  echo "    sudo systemctl restart docker"
  exit 1
fi

echo "🧠 Увімкнення форвардингу та br_netfilter…"
sudo modprobe br_netfilter || true
sudo sysctl -w net.bridge.bridge-nf-call-iptables=1 >/dev/null
sudo sysctl -w net.ipv4.ip_forward=1 >/dev/null

# Формуємо множини портів у синтаксисі nft
TCP_SET="$(IFS=, ; echo "{${TCP_PORTS[*]}}")"
UDP_SET="$(IFS=, ; echo "{${UDP_PORTS[*]}}")"

# Створюємо/пересоздаємо наші таблиці, щоб не чіпати Docker-ланцюги
# - NAT: окрема таблиця 'ip mikrotik_nat' з пріоритетом -101 (перед стандартним dstnat -100)
# - FILTER: окрема таблиця 'inet mikrotik_fw' для дозволів INPUT/FORWARD
NFT_SCRIPT=$(cat <<EOF
flush table ip mikrotik_nat
flush table inet mikrotik_fw

table ip mikrotik_nat {
  chain prerouting {
    type nat hook prerouting priority -101; policy accept;
    # DNAT на MikroTik для TCP портів
    tcp dport $TCP_SET ip daddr $SRC_IP dnat to $DST_IP
    # DNAT на MikroTik для UDP портів
    udp dport $UDP_SET ip daddr $SRC_IP dnat to $DST_IP
  }
  chain postrouting {
    type nat hook postrouting priority 100; policy accept;
    # Маскарадинг для зворотного трафіку до MikroTik
    ip daddr $DST_IP masquerade
    # Маскарадинг для Docker-підмережі (щоб повернення пройшло через хост)
    ip daddr 172.21.0.0/16 masquerade
  }
}

table inet mikrotik_fw {
  chain input {
    type filter hook input priority 0; policy accept;
    # Дозволяємо доступ з LAN до портів на хості
    ip saddr $LAN_SUBNET tcp dport $TCP_SET accept
    ip saddr $LAN_SUBNET udp dport $UDP_SET accept
  }
  chain forward {
    type filter hook forward priority 0; policy accept;
    # Дозволяємо форвардинг трафіку до MikroTik на потрібні порти
    ip daddr $DST_IP tcp dport $TCP_SET accept
    ip daddr $DST_IP udp dport $UDP_SET accept
  }
}
EOF
)

echo "🧱 Застосовую nft-правила…"
echo "$NFT_SCRIPT" | sudo nft -f -

echo "✅ Готово."
echo "Перевірка правил:"
echo "  sudo nft list table ip mikrotik_nat"
echo "  sudo nft list table inet mikrotik_fw"
echo
echo "Поради:"
echo " - Якщо ти змінюватимеш порти або IP, просто знову запусти скрипт."
echo " - Для видалення правил: 'sudo nft delete table ip mikrotik_nat; sudo nft delete table inet mikrotik_fw'."
