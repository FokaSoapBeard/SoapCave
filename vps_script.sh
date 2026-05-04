#!/bin/bash
set -euo pipefail

# Проверка прав root
if [ "$EUID" -ne 0 ]; then
    echo "❌ Ошибка: скрипт нужно запускать от имени root (через sudo bash setup_vps.sh)"
    exit 1
fi

echo "=== 🛡️ Автоматическая настройка безопасности VPS ==="

# 1. Интерактивный ввод
read -s -p "🔑 Введите пароль для пользователя urf: " USER_PASS
echo
read -r -p "📝 Вставьте SSH публичный ключ (одной строкой): " SSH_KEY
echo
read -r -p "🌐 Введите IP-адрес(а) для Fail2ban (через пробел): " FAIL2BAN_IPS
echo

if [ -z "$SSH_KEY" ] || [ -z "$FAIL2BAN_IPS" ]; then
    echo "❌ SSH ключ и IP не могут быть пустыми. Запустите скрипт заново."
    exit 1
fi

# 2. Создание пользователя
echo "[1/7] Создаём пользователя urf..."
useradd -m -s /bin/bash urf
echo "urf:${USER_PASS}" | chpasswd
usermod -aG sudo urf

# 3. Настройка SSH ключа
echo "[2/7] Настраиваем SSH авторизацию..."
mkdir -p /home/urf/.ssh
echo "$SSH_KEY" > /home/urf/.ssh/authorized_keys
chown -R urf:urf /home/urf/.ssh
chmod 700 /home/urf/.ssh
chmod 600 /home/urf/.ssh/authorized_keys

# 4. Безопасная правка sshd_config
echo "[3/7] Меняем настройки SSH..."
SSH_CONF="/etc/ssh/sshd_config"
cp "$SSH_CONF" "${SSH_CONF}.bak.$(date +%F_%T)"

update_ssh_param() {
    local param="$1" val="$2"
    if grep -qE "^[#[:space:]]*${param}[[:space:]]" "$SSH_CONF"; then
        sed -i "s/^[#[:space:]]*${param}[[:space:]].*/${param} ${val}/" "$SSH_CONF"
    else
        echo "${param} ${val}" >> "$SSH_CONF"
    fi
}

update_ssh_param "Port" "22022"
update_ssh_param "PermitRootLogin" "no"
update_ssh_param "PasswordAuthentication" "no"
update_ssh_param "AuthenticationMethods" "publickey"
update_ssh_param "MaxAuthTries" "3"
update_ssh_param "LoginGraceTime" "30"
update_ssh_param "MaxSessions" "3"

# Перезапуск SSH (работает и на Debian/Ubuntu, и на RHEL/CentOS)
systemctl restart ssh 2>/dev/null || systemctl restart sshd

# 5. UFW Firewall
echo "[4/7] Устанавливаем и настраиваем UFW..."
export DEBIAN_FRONTEND=noninteractive
apt update -y && apt install -y ufw
ufw default deny incoming
ufw default allow outgoing
ufw allow 22022/tcp
ufw allow 443/tcp
ufw allow 80/tcp
ufw allow 443/udp
ufw allow 8444/tcp
ufw allow 8445/tcp
ufw allow 1080/tcp
ufw --force enable
ufw status verbose

# 6. Fail2ban
echo "[5/7] Устанавливаем и настраиваем Fail2ban..."
apt install -y fail2ban
systemctl enable fail2ban

# Гарантируем наличие логов (критично для минимальных образов)
touch /var/log/auth.log
touch /var/log/syslog 2>/dev/null || true

# Пишем конфиг ДО первого запуска службы
cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
ignoreip = 127.0.0.1/8 ::1 ${FAIL2BAN_IPS}
bantime  = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled  = true
port     = 22022
filter   = sshd
logpath  = /var/log/auth.log
backend  = polling
maxretry = 5
EOF

# Запускаем службу
systemctl restart fail2ban

# Ждём, пока fail2ban-server не станет отвечать на команды клиента
echo "⏳ Ожидание инициализации fail2ban..."
for i in {1..15}; do
    if fail2ban-client status >/dev/null 2>&1; then
        echo "✅ Служба готова к работе."
        break
    fi
    sleep 1
done

# Проверяем конкретно jail sshd
if fail2ban-client status sshd >/dev/null 2>&1; then
    echo "📊 Статус Fail2ban:"
    fail2ban-client status sshd
    fail2ban-client get sshd ignoreip
    echo "✅ Jail 'sshd' активен и работает."
else
    echo "⚠️  Jail не загрузился. Диагностика:"
    systemctl status fail2ban --no-pager -l
    journalctl -u fail2ban --no-pager -n 15
fi

# 7. BBR
echo "[6/7] Включаем TCP BBR..."
enable_bbr() {
    if sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null | grep -q '^bbr$'; then
        echo "✅ BBR congestion control уже включён."
    else
        echo "🚀 Включаем TCP BBR congestion control..."
        grep -qF 'net.core.default_qdisc=fq' /etc/sysctl.conf \
            || echo 'net.core.default_qdisc=fq' >> /etc/sysctl.conf
        grep -qF 'net.ipv4.tcp_congestion_control=bbr' /etc/sysctl.conf \
            || echo 'net.ipv4.tcp_congestion_control=bbr' >> /etc/sysctl.conf
        sysctl -p >/dev/null 2>&1
    fi
}
enable_bbr

# 8. Xray
echo "[7/7] Установка VPN..."

echo "⏳ Установка xRay..."
sudo bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
echo "⏳ Установка nginx..."
sudo apt install nginx -y

# cоздаем папку для сертификатов Xray
sudo mkdir -p /opt/xray_cert

# обычно xray в noname, nogroup, дамем права
sudo chown root:nogroup /opt/xray_cert && sudo chmod 750 /opt/xray_cert

echo "⏳ Генерация ключей..."

# Reality
R_UUID=$(xray uuid | xargs)
R_X25519=$(xray x25519)
R_PRIV=$(echo "$R_X25519" | grep -i "private" | awk -F': ' '{print $2}' | xargs)
R_PUB=$(echo "$R_X25519" | grep -i "public" | awk -F': ' '{print $2}' | xargs)
R_SHORT=$(openssl rand -hex 8)

# XHTTP
X_UUID=$(xray uuid | xargs)
X_X25519=$(xray x25519)
X_PRIV=$(echo "$X_X25519" | grep -i "private" | awk -F': ' '{print $2}' | xargs)
X_PUB=$(echo "$X_X25519" | grep -i "public" | awk -F': ' '{print $2}' | xargs)
X_SHORT=$(openssl rand -hex 8)
X_PASS=$(openssl rand -hex 24)

# Shadowsocks
SS_PASS=$(openssl rand -hex 32)

# конфиг xray
sudo tee /usr/local/etc/xray/config.json > /dev/null <<EOF
{
  "log": { "loglevel": "none" },
  "dns": {
    "servers": [ "https+local://1.1.1.1/dns-query", "localhost" ]
  },
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      { "ip": ["geoip:private"], "outboundTag": "block" },
      { "domain": ["geosite:category-ads-all"], "outboundTag": "block" }
    ]
  },
  "inbounds": [
    {
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${R_UUID}",
            "flow": "xtls-rprx-vision",
            "level": 0,
            "email": "admin@phocarobotics.xyz"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "www.microsoft.com:443",
          "xver": 0,
          "serverNames": ["www.microsoft.com", "microsoft.com"],
          "privateKey": "${R_PRIV}",
          "shortIds": ["${R_SHORT}"]
        }
      }
    }
  ],
  "outbounds": [
    { "tag": "direct", "protocol": "freedom" },
    { "tag": "block", "protocol": "blackhole" }
  ]
}
EOF

# Валидация конфига
if xray run -config /usr/local/etc/xray/config.json -test >/dev/null 2>&1; then
    sudo systemctl restart xray
    echo "✅ Конфиг применён"
else
    echo "❌ Ошибка в конфиге! Проверьте:"
    cat /usr/local/etc/xray/config.json
    exit 1
fi

# === ГЕНЕРАЦИЯ ССЫЛОК ДЛЯ ИМПОРТА (v2ray / xray) ===

# Определяем ваш домен (замените на реальный!)
DOMAIN="${DOMAIN:-phocarobotics.xyz}"
PORT="${PORT:-443}"

# Функция URL-кодирования для base64 (заменяет + / = на %2B %2F %3D)
url_encode() {
  echo -n "$1" | sed 's/+/%2B/g; s/\//%2F/g; s/=/%3D/g'
}

# 1️⃣ Reality TCP (порт 443, Vision)
R_LINK="vless://${R_UUID}@${DOMAIN}:${PORT}?security=reality&pbk=$(url_encode "$R_PUB")&sid=${R_SHORT}&sni=www.microsoft.com&fp=chrome&type=tcp&flow=xtls-rprx-vision#Reality-TCP"

# 2️⃣ XHTTP + Reality (порт 8445)
X_LINK="vless://${X_UUID}@${DOMAIN}:8445?security=reality&pbk=$(url_encode "$X_PUB")&sid=${X_SHORT}&sni=www.microsoft.com&fp=chrome&type=xhttp&path=%2F${X_PASS}&mode=stream-one#XHTTP-Reality"

# 3️⃣ Reality TCP (порт 8444, альтернативный)
R2_LINK="vless://${R_UUID}@${DOMAIN}:8444?security=reality&pbk=$(url_encode "$R_PUB")&sid=${R_SHORT}&sni=www.microsoft.com&fp=chrome&type=tcp&flow=xtls-rprx-vision#Reality-Alt"

# 4️⃣ Shadowsocks 2022 (порт 1080)
# Формат: ss://base64(method:password)@host:port#Remark
SS_RAW="2022-blake3-aes-256-gcm:${SS_PASS}"
SS_B64=$(echo -n "$SS_RAW" | base64 -w0)
SS_LINK="ss://${SS_B64}@${DOMAIN}:1080#Shadowsocks-2022"

# Экспортируем ссылки, чтобы использовать в финальном выводе
export R_LINK X_LINK R2_LINK SS_LINK

cat <<EOF

========================================================
                Выполнение закончено
========================================================

 [Установки]
 xRay(nogroup): OK
 nginx: OK
 сертификаты: /opt/xray_cert
 права(nogroup): ОК

 [Reality]
 UUID:        $R_UUID
 PrivateKey:  $R_PRIV
 PublicKey:   $R_PUB
 ShortId:     $R_SHORT

 [XHTTP]
 UUID:        $X_UUID
 PrivateKey:  $X_PRIV
 PublicKey:   $X_PUB
 ShortId:     $X_SHORT
 LinkPass:        /${X_PASS}

 [Shadowsocks]
 Password:    $SS_PASS

 ========================================================
  🔗 Ссылки для импорта (кликните или скопируйте):
========================================================


🔐 Копировать вот эту (443, Reality):
$R_LINK

Эти будут активны с обновлением конфига:

🌐 XHTTP + Reality (8445):
$X_LINK

🔄 Reality Alt (8444):
$R2_LINK

🛡️ Shadowsocks 2022 (1080):
$SS_LINK

========================================================
  💡 Все значения содержат только [0-9a-f] и стандартный UUID.
     Экранирование для HTML/JSON/URL НЕ требуется.
     Ссылки уже содержат необходимое URL-кодирование.
========================================================
EOF
