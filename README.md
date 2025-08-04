# MikroTik CHR як кореневий маршрутизатор для контейнерів

Цей проєкт демонструє, як розгорнути MikroTik Cloud Hosted Router (CHR) у Docker як кореневий маршрутизатор для інших контейнерів. Такий підхід дозволяє реалізувати повноцінну маршрутизацію, VLAN/VRF, VPN, NAT, Firewall, WireGuard та інші функції, доступні в MikroTik, прямо всередині контейнерної інфраструктури.
Хоча задумака спрацювала не з першого разу але я показую як я це реалізував.

Для почтку вам треба підняти docker контейнер mikrotik-chr з інтерфейсами. В моєму випаку я реалізував 5 інтерерфейсів mikrotik_net_a та mikrotik_net_e це останній. Де в мене mikrotik_net_a виконує роль вхідного інтерфейсу для Wan 

---

## 🔧 Docker Compose (`docker-compose.yml`)

```yaml
version: "3.8"

services:
  mikrotik-chr:
    image: mikrotik/chr
    container_name: chr-router
    privileged: true
    restart: unless-stopped
    ports:
      - "8291:8291"            # WinBox
      - "51820:51820/udp"      # WireGuard
      - "1701:1701/udp"        # L2TP VPN
    networks:
      mikrotik_net_a:
        ipv4_address: 172.21.0.2
      mikrotik_net_b:
        ipv4_address: 192.168.1.2
      mikrotik_net_c:
        ipv4_address: 192.168.2.2
      mikrotik_net_d:
        ipv4_address: 192.168.3.2
      mikrotik_net_e:
        ipv4_address: 192.168.4.2

networks:
  mikrotik_net_a:
    name: mikrotik_net_a
    driver: bridge
    ipam:
      config:
        - subnet: 172.21.0.0/24
          gateway: 172.21.0.1
  mikrotik_net_b:
    name: mikrotik_net_b
    driver: bridge
    ipam:
      config:
        - subnet: 192.168.1.0/24
          gateway: 192.168.1.1
  mikrotik_net_c:
    name: mikrotik_net_c
    driver: bridge
    ipam:
      config:
        - subnet: 192.168.2.0/24
          gateway: 192.168.2.1
  mikrotik_net_d:
    name: mikrotik_net_d
    driver: bridge
    ipam:
      config:
        - subnet: 192.168.3.0/24
          gateway: 192.168.3.1
  mikrotik_net_e:
    name: mikrotik_net_e
    driver: bridge
    ipam:
      config:
        - subnet: 192.168.4.0/24
          gateway: 192.168.4.1
```

---

## 📜 MikroTik CHR RSC скрипт (ініціалізація маршрутизатора)
Далі я створив RSC-скрипт
Цей RSC-скрипт виконує такі дії:

- очищення всіх попередніх налаштувань
- налаштування WAN (DHCP + маршрут по замовчуванню)
- розподіл LAN по 4 інтерфейсах
- конфігурацію DHCP серверів
- додавання WireGuard
- базові правила фаєрволу

Файл: `init-config.rsc`

> 🔽 (повний вміст див. у вихідному файлі або окремому розділі)

---

Пісял ціх дії нам треба було якось реалізувати дсотуп до мережі інтернет та можливість підклчення до цього MikroTik із зовні бо так як із середини ми не можемо отримати доступ до контейнерів окрім CLI з docker. Я використував WireGuard та пропрос портів для цього впн, а також зробив додаткоово проброс для L2TP для подалших дії на майбутне та порт 8291 для WinBox. 
Для повної реалізації було створена bash скрип iptables-setup.sh для NAT/DNAT через iptables.

## 🔒 Bash-скрипт для NAT/DNAT через iptables

Скрипт `iptables-setup.sh` дозволяє налаштувати DNAT та маскарадинг для доступу до MikroTik із зовнішньої LAN мережі. Він автоматично перемикає iptables на `legacy`, додає DNAT, FORWARD і MASQUERADE правила, і активує IP forwarding.

### Основні задачі:

- DNAT/forward портів (WinBox, WireGuard, L2TP)
- Маскарадинг для зворотного трафіку
- Дозвіл трафіку з локальної мережі
- Вивід інструкції для перевірки

Файл: `iptables-setup.sh`

---

## ✅ Підключення клієнтів через WireGuard

WireGuard інтерфейс `wg0` слухає на `51820/udp`, має адресу `10.0.0.1/24` і дозволяє доступ клієнтам `10.0.0.2` та `10.0.0.3`. Правила фаєрволу дозволяють granular доступ до підмереж, зокрема:

- `10.0.0.2` має повний доступ до всіх LAN
- `10.0.0.3` обмежено (тільки до деяких LAN)

---

## 🧪 Тестування та перевірка

1. **WinBox підключення:** IP `192.168.88.200:8291` 192.168.88.200 це IP мого компьютера в вас може бути інший. 
2. **WireGuard клієнти:** через публічні ключі
3. **DHCP перевірка:** контейнери отримують IP від MikroTik
4. **Маршрутизація:** з інших контейнерів є доступ до зовнішньої мережі через MikroTik

---

## 📌 Примітки

- Контейнеру `mikrotik-chr` **потрібен режим **`` для коректної роботи з мережами.
- Скрипти слід виконувати з правами `sudo`.
- MikroTik CHR підтримує RouterOS повністю: можна розгортати hotspot, VPN, tunnels, firewall scripts тощо.

---

## 📂 Структура репозиторію

```
├── docker-compose.yml
├── init-config.rsc
├── iptables-setup.sh
└── README.md (ця стаття)
```

---

## 📎 TODO

-

---

Залишайся з нами, далі буде 🔥

