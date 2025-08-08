# MikroTik CHR як кореневий маршрутизатор для контейнерів

Цей проєкт демонструє, як розгорнути MikroTik Cloud Hosted Router (CHR) у Docker як кореневий маршрутизатор для інших контейнерів. Такий підхід дозволяє реалізувати повноцінну маршрутизацію, VLAN/VRF, VPN, NAT, Firewall, WireGuard та інші функції, доступні в MikroTik, прямо всередині контейнерної інфраструктури.

Хоча ідея не спрацювала з першого разу, я показую, як саме вдалося реалізувати робоче рішення.

Для початку потрібно запустити контейнер `mikrotik-chr` з кількома мережевими інтерфейсами. У моєму випадку реалізовано 5 інтерфейсів — від `mikrotik_net_a` до `mikrotik_net_e`, де `mikrotik_net_a` виконує роль вхідного інтерфейсу для WAN.

``
[HOST] (фізично в мережі 192.168.88.0/24)
    ↕
[Docker Bridge mikrotik_net_a] → 172.21.0.1 (default gateway у bridge)
    ↕
[MikroTik CHR container]  → ether1 = 172.21.0.2
                          → ether2 = 192.168.1.1
                          → ether3 = 192.168.2.1
                          → ether4 = 192.168.3.1
                          → ether5 = 192.168.4.1
    ↕
[Інші Docker-контейнери в мережах mikrotik_net_b → mikrotik_net_e]

``

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

Цей RSC-скрипт виконує:

* очищення всіх попередніх налаштувань
* налаштування WAN (DHCP + маршрут за замовчуванням)
* розподіл LAN по 4 інтерфейсах
* конфігурацію DHCP-серверів
* додавання WireGuard
* базові правила фаєрволу

Файл: `init-config.rsc`

> 🔽 [повний вміст див. у файлі init-config.rsc](./init-config.rsc)

---

``⚠️ Примітка: Оскільки ми реалізували багато інтерфейсів, Docker не виконуватиме маскарадинг (NAT) до mikrotik_net_a автоматично — тому потрібен ручний контроль за маршрутизацією та NAT.``

Після цього потрібно забезпечити доступ до Інтернету і можливість підключення до MikroTik із зовнішньої мережі. Оскільки доступ до контейнера ззовні неможливий напряму (окрім CLI через Docker), я використав WireGuard і пробросив порти для VPN. Також додатково налаштовано L2TP і порт 8291 для WinBox.

Для повної реалізації створено bash-скрипт `iptables-setup.sh`, який відповідає за DNAT/NAT через iptables.

## 🔒 Bash-скрипт для NAT/DNAT через iptables

Скрипт `iptables-setup.sh` дозволяє налаштувати DNAT та маскарадинг для доступу до MikroTik із зовнішньої LAN-мережі. Він автоматично перемикає iptables на `legacy`, додає DNAT, FORWARD і MASQUERADE правила та активує IP forwarding.

### Основні задачі:

* DNAT/forward портів (WinBox, WireGuard, L2TP)
* Маскарадинг для зворотного трафіку
* Дозвіл трафіку з локальної мережі
* Виведення інструкції для перевірки

Файл: `iptables-setup.sh`
> 🔽 [повний вміст див. у файлі iptables-setup.sh](./iptables-setup.sh)
---

## ✅ Підключення клієнтів через WireGuard

WireGuard-інтерфейс `wg0` слухає на `51820/udp`, має адресу `10.0.0.1/24` і дозволяє доступ клієнтам `10.0.0.2` та `10.0.0.3`. Правила фаєрволу дозволяють гнучкий (granular) доступ до підмереж:

* `10.0.0.2` має повний доступ до всіх LAN
* `10.0.0.3` обмежено (доступ лише до деяких підмереж)

---

## 🧪 Тестування та перевірка

1. **WinBox підключення:** IP `192.168.88.200:8291` (192.168.88.200 — IP мого комп'ютера; у вас може бути інший)
2. **WireGuard клієнти:** через публічні ключі
3. **DHCP перевірка:** контейнери отримують IP від MikroTik ``нажаль ця опція не спрацьвала із-за особливостей Docker та DHCP сервер не може раздовати адреса так як докер сам автоматично призначає адресацію згідно підмережі в якому вона знаходиться контейнер. Але ви самі можете у yml вказати адрес за вашим бажанням згідно підмережі в якому буде знаходитися контейнер``
4. **Маршрутизація:** з інших контейнерів є доступ до зовнішньої мережі через MikroTik

---

## 📌 Примітки

* Контейнеру `mikrotik-chr` **потрібен режим `privileged: true`** для коректної роботи з мережами
* Скрипти слід виконувати з правами `sudo`
* MikroTik CHR підтримує RouterOS повністю: можна розгортати hotspot, VPN, tunnels, firewall scripts тощо в моєму випадку я розгорнув VPN це WireGuard. 

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

* [ ] Додати приклад `ubuntu-desktop` з DHCP без `ipv4_address`
* [ ] Додати схему мережі (SVG або PNG)
* [ ] Описати типові помилки при налаштуванні

---

Залишайся з нами, далі буде 🔥
якщо знайшли помилку або хочете обговорити пишить:
[📲 Telegram](https://t.me/RifatIsmailov)
[🔗 LinkedIn](https://www.linkedin.com/in/твоє_імʼя/)
