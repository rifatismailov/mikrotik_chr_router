# ❌ Очистка попередніх налаштувань
/ip pool remove [find]
/ip dhcp-server remove [find]
/ip dhcp-server network remove [find]
/ip address remove [find]
/ip firewall nat remove [find]
/ip firewall filter remove [find]
/interface wireguard remove [find]
/interface wireguard peers remove [find]
/ip dhcp-client remove [find]

# 🌐 WAN (ether1 — mikrotik_net_a 172.21.0.0/24)
/ip dhcp-client add interface=ether1 disabled=no
/ip address add address=172.21.0.2/24 interface=ether1
/ip route add dst-address=0.0.0.0/0 gateway=172.21.0.1
/ip firewall nat add chain=srcnat out-interface=ether1 action=masquerade

# 🖧 LAN
# ether2 → mikrotik_net_b (192.168.1.0/24)
/ip address add address=192.168.1.1/24 interface=ether2
# ether3 → mikrotik_net_c (192.168.2.0/24)
/ip address add address=192.168.2.1/24 interface=ether3
# ether4 → mikrotik_net_d (192.168.3.0/24)
/ip address add address=192.168.3.1/24 interface=ether4
# ether5 → mikrotik_net_e (192.168.4.0/24)
/ip address add address=192.168.4.1/24 interface=ether5

/ip pool add name=dhcp_pool_1 ranges=192.168.1.200-192.168.1.254
/ip pool add name=dhcp_pool_2 ranges=192.168.2.200-192.168.2.254
/ip pool add name=dhcp_pool_3 ranges=192.168.3.200-192.168.3.254
/ip pool add name=dhcp_pool_4 ranges=192.168.4.200-192.168.4.254

/ip dhcp-server add name=dhcp1 interface=ether2 address-pool=dhcp_pool_1 disabled=no
/ip dhcp-server add name=dhcp2 interface=ether3 address-pool=dhcp_pool_2 disabled=no
/ip dhcp-server add name=dhcp3 interface=ether4 address-pool=dhcp_pool_3 disabled=no
/ip dhcp-server add name=dhcp4 interface=ether5 address-pool=dhcp_pool_4 disabled=no

/ip dhcp-server network add address=192.168.1.0/24 gateway=192.168.1.1 dns-server=8.8.8.8
/ip dhcp-server network add address=192.168.2.0/24 gateway=192.168.2.1 dns-server=8.8.8.8
/ip dhcp-server network add address=192.168.3.0/24 gateway=192.168.3.1 dns-server=8.8.8.8
/ip dhcp-server network add address=192.168.4.0/24 gateway=192.168.4.1 dns-server=8.8.8.8

# 🔐 WireGuard
/interface wireguard add name=wg0 listen-port=51820 private-key="K4UZK6WqNc2C8gNX03nKnnTnEvm+xlPKh7vM97r8yHs="
/ip address add address=10.0.0.1/24 interface=wg0

/interface wireguard peers add interface=wg0 public-key="lQ2eKOuPsbGUcy8PB8b5qpnIN+Q5gzb42FEruz3aWBk=" allowed-address=10.0.0.2/32
/interface wireguard peers add interface=wg0 public-key="aQk4DnOzKeNoF9RDCwp4EnoHUPdb+Ev3s5v8TfnB9zB=" allowed-address=10.0.0.3/32

# 🔥 Firewall (послідовність має значення)
/ip firewall filter add chain=input src-address=172.21.0.0/16 action=accept comment="✅ Дозволяємо ВСЕ з LAN"
/ip firewall filter add chain=input connection-state=established,related action=accept comment="Established/Related"
/ip firewall filter add chain=input protocol=icmp action=accept comment="Ping"
/ip firewall filter add chain=input protocol=tcp src-address=172.21.0.0/16 dst-port=8291 action=accept comment="Allow Winbox from LAN"
/ip firewall filter add chain=input in-interface=ether1 action=drop comment="❌ Drop all else from WAN"

/ip firewall filter add chain=forward src-address=10.0.0.2 dst-address=192.168.1.0/24 action=accept
/ip firewall filter add chain=forward src-address=10.0.0.2 dst-address=192.168.2.0/24 action=accept
/ip firewall filter add chain=forward src-address=10.0.0.2 dst-address=192.168.3.0/24 action=accept
/ip firewall filter add chain=forward src-address=10.0.0.2 dst-address=192.168.4.0/24 action=accept

/ip firewall filter add chain=forward src-address=10.0.0.3 dst-address=192.168.2.0/24 action=accept
/ip firewall filter add chain=forward src-address=10.0.0.3 dst-address=192.168.3.0/24 action=accept
/ip firewall filter add chain=forward src-address=10.0.0.3 action=drop comment="Блокуємо доступ WG2 до решти"

# ✅ Дозвіл ВСІХ портів з LAN (включно з Winbox)
/ip firewall filter add chain=input src-address=172.21.0.0/16 action=accept comment="Allow ALL from LAN 172.21.0.0/16"

# ✅ Увімкнення Winbox-сервісу
/ip service enable winbox
/ip service set winbox address=0.0.0.0/0 port=8291
