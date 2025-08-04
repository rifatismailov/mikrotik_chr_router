#!/bin/bash

SRC_IP="192.168.88.200"      # IP хоста (має бути у LAN!)
DST_IP="172.21.0.2"          # IP MikroTik у Docker bridge
LAN_SUBNET="192.168.88.0/24" # LAN підмережа

PORTS=("8291/tcp" "51820/udp" "1701/udp")

echo "➡️ Перемикаю на iptables-legacy..."
sudo update-alternatives --set iptables /usr/sbin/iptables-legacy
sudo update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy

echo "♻️ Очищаю старі правила..."
for PORT_PROTO in "${PORTS[@]}"; do
  PORT="${PORT_PROTO%/*}"
  PROTO="${PORT_PROTO#*/}"

  sudo iptables -t nat -D PREROUTING -p $PROTO -d $SRC_IP --dport $PORT -j DNAT --to-destination $DST_IP:$PORT 2>/dev/null
  sudo iptables -D FORWARD -p $PROTO -d $DST_IP --dport $PORT -j ACCEPT 2>/dev/null
  sudo iptables -D INPUT -p $PROTO -s $LAN_SUBNET --dport $PORT -j ACCEPT 2>/dev/null
done

echo "✅ Додаю нові DNAT/forward правила..."
for PORT_PROTO in "${PORTS[@]}"; do
  PORT="${PORT_PROTO%/*}"
  PROTO="${PORT_PROTO#*/}"

  sudo iptables -t nat -A PREROUTING -p $PROTO -d $SRC_IP --dport $PORT -j DNAT --to-destination $DST_IP:$PORT -m comment --comment "Forward $PORT/$PROTO to MikroTik"
  sudo iptables -A FORWARD -p $PROTO -d $DST_IP --dport $PORT -j ACCEPT -m comment --comment "Allow $PORT/$PROTO to MikroTik"
done

echo "🔁 Додаю MASQUERADE для зворотнього трафіку..."
sudo iptables -t nat -C POSTROUTING -d $DST_IP -j MASQUERADE 2>/dev/null || \
sudo iptables -t nat -A POSTROUTING -d $DST_IP -j MASQUERADE -m comment --comment "MASQUERADE for MikroTik return path"

sudo iptables -t nat -C POSTROUTING -d 172.21.0.0/16 -j MASQUERADE 2>/dev/null || \
sudo iptables -t nat -A POSTROUTING -d 172.21.0.0/16 -j MASQUERADE -m comment --comment "MASQUERADE for Docker subnet"

echo "🌐 Включаю маршрутизацію (ip_forward)..."
sudo sysctl -w net.ipv4.ip_forward=1

echo "🚪 Дозволяю доступ до портів із LAN ($LAN_SUBNET)..."
for PORT_PROTO in "${PORTS[@]}"; do
  PORT="${PORT_PROTO%/*}"
  PROTO="${PORT_PROTO#*/}"

  sudo iptables -C INPUT -p $PROTO -s $LAN_SUBNET --dport $PORT -j ACCEPT 2>/dev/null || \
  sudo iptables -A INPUT -p $PROTO -s $LAN_SUBNET --dport $PORT -j ACCEPT -m comment --comment "Allow $PORT/$PROTO from LAN"
done

echo "✅ Готово. Перевір із іншого комп'ютера:"
echo "👉 WinBox → $SRC_IP або telnet $SRC_IP 8291"