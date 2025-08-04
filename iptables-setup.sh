#!/bin/bash

# 🧾 Параметри конфігурації
SRC_IP="192.168.88.200"      # IP-адреса хоста, до якого буде звернення з локальної мережі (LAN)
DST_IP="172.21.0.2"          # IP-адреса MikroTik у мережі Docker (bridge), куди перенаправляється трафік
LAN_SUBNET="192.168.88.0/24" # Підмережа локальної мережі, з якої дозволено доступ

# 🔁 Порти, які треба переадресувати (DNAT) у форматі порт/протокол
PORTS=("8291/tcp" "51820/udp" "1701/udp")
# 8291/tcp  – WinBox порт
# 51820/udp – WireGuard VPN
# 1701/udp  – L2TP VPN

# 🔄 Переключення на iptables-legacy (для сумісності зі старим Docker/iptables API)
echo "➡️ Перемикаю на iptables-legacy..."
sudo update-alternatives --set iptables /usr/sbin/iptables-legacy
sudo update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy

# 🧹 Видалення старих правил DNAT, FORWARD, INPUT
echo "♻️ Очищаю старі правила..."
for PORT_PROTO in "${PORTS[@]}"; do
  PORT="${PORT_PROTO%/*}"   # Отримати порт (до символу '/')
  PROTO="${PORT_PROTO#*/}"  # Отримати протокол (після символу '/')

  sudo iptables -t nat -D PREROUTING -p $PROTO -d $SRC_IP --dport $PORT -j DNAT --to-destination $DST_IP:$PORT 2>/dev/null
  sudo iptables -D FORWARD -p $PROTO -d $DST_IP --dport $PORT -j ACCEPT 2>/dev/null
  sudo iptables -D INPUT -p $PROTO -s $LAN_SUBNET --dport $PORT -j ACCEPT 2>/dev/null
done

# ➕ Додавання нових правил DNAT (перенаправлення портів) і дозволу трафіку у FORWARD
echo "✅ Додаю нові DNAT/forward правила..."
for PORT_PROTO in "${PORTS[@]}"; do
  PORT="${PORT_PROTO%/*}"
  PROTO="${PORT_PROTO#*/}"

  sudo iptables -t nat -A PREROUTING -p $PROTO -d $SRC_IP --dport $PORT -j DNAT --to-destination $DST_IP:$PORT -m comment --comment "Forward $PORT/$PROTO to MikroTik"
  sudo iptables -A FORWARD -p $PROTO -d $DST_IP --dport $PORT -j ACCEPT -m comment --comment "Allow $PORT/$PROTO to MikroTik"
done

# 🌐 MASQUERADE – підміна джерела для зворотнього трафіку до LAN та Docker
echo "🔁 Додаю MASQUERADE для зворотнього трафіку..."
sudo iptables -t nat -C POSTROUTING -d $DST_IP -j MASQUERADE 2>/dev/null || \
sudo iptables -t nat -A POSTROUTING -d $DST_IP -j MASQUERADE -m comment --comment "MASQUERADE for MikroTik return path"

sudo iptables -t nat -C POSTROUTING -d 172.21.0.0/16 -j MASQUERADE 2>/dev/null || \
sudo iptables -t nat -A POSTROUTING -d 172.21.0.0/16 -j MASQUERADE -m comment --comment "MASQUERADE for Docker subnet"

# 🧭 Увімкнення IP маршрутизації (потрібно для FORWARD)
echo "🌐 Включаю маршрутизацію (ip_forward)..."
sudo sysctl -w net.ipv4.ip_forward=1

# 🔓 Дозвіл вхідних з'єднань із локальної мережі до перелічених портів
echo "🚪 Дозволяю доступ до портів із LAN ($LAN_SUBNET)..."
for PORT_PROTO in "${PORTS[@]}"; do
  PORT="${PORT_PROTO%/*}"
  PROTO="${PORT_PROTO#*/}"

  sudo iptables -C INPUT -p $PROTO -s $LAN_SUBNET --dport $PORT -j ACCEPT 2>/dev/null || \
  sudo iptables -A INPUT -p $PROTO -s $LAN_SUBNET --dport $PORT -j ACCEPT -m comment --comment "Allow $PORT/$PROTO from LAN"
done

# ✅ Завершення роботи скрипта
echo "✅ Готово. Перевір із іншого комп'ютера:"
echo "👉 WinBox → $SRC_IP або telnet $SRC_IP 8291"
