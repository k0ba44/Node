#!/bin/bash

# Остановка скрипта при ошибке и настройка цвета
set -e
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m' # No Color

# Проверка запуска от имени root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Ошибка: Этот скрипт должен быть запущен с правами root (sudo).${NC}"
   exit 1
fi

# Функция для вопросов с выбором Yes/No (по умолчанию Yes)
ask_yes_no() {
    while true; do
        echo -ne "${YELLOW}$1 [Y/n]: ${NC}"
        read -r yn
        case $yn in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            "" ) return 0;; # По умолчанию Yes
            * ) echo "Пожалуйста, ответьте yes (y) или no (n).";;
        esac
    done
}

echo -e "${GREEN}=== Интерактивный установщик ноды ===${NC}\n"

# --- 1. Установка Docker ---
if ask_yes_no "Установить Docker?"; then
    echo -e "${GREEN}Настройка Docker...${NC}"
    if command -v docker &> /dev/null; then
        echo "Docker уже установлен, пропускаем скачивание."
    else
        curl -fsSL https://get.docker.com | sh
        echo "Docker успешно установлен."
    fi
else
    echo "Пропуск установки Docker."
fi
echo ""

# --- 2. Настройка remnanode ---
if ask_yes_no "Настроить и запустить remnanode?"; then
    echo -e "${GREEN}Настройка /opt/remnanode...${NC}"
    mkdir -p /opt/remnanode
    cd /opt/remnanode

    echo "--------------------------------------------------------"
    echo "Сейчас откроется редактор nano для docker-compose.yml."
    echo "Вставь нужный код, сохрани (Ctrl+O -> Enter) и выйди (Ctrl+X)."
    echo "--------------------------------------------------------"
    read -p "Нажми Enter, чтобы открыть редактор..."
    
    nano docker-compose.yml

    # Проверяем, не пустой ли файл, прежде чем запускать контейнеры
    if [[ -s docker-compose.yml ]]; then
        echo -e "${GREEN}Запуск remnanode...${NC}"
        docker compose up -d
    else
        echo -e "${RED}Файл docker-compose.yml пуст! Запуск отменен.${NC}"
    fi
else
    echo "Пропуск настройки remnanode."
fi
echo ""

# --- 3. Настройка selfsteel (Caddy Proxy) ---
if ask_yes_no "Настроить веб-сервер Caddy (selfsteel) и заглушку?"; then
    echo -e "${GREEN}Настройка /opt/selfsteel...${NC}"
    mkdir -p /opt/selfsteel
    cd /opt/selfsteel

    echo "Создание Caddyfile..."
    cat << 'EOF' > Caddyfile
{
    https_port {$SELF_STEAL_PORT}
    default_bind 127.0.0.1
    servers {
        listener_wrappers {
            proxy_protocol {
                allow 127.0.0.1/32
            }
            tls
        }
    }
    auto_https disable_redirects
}

http://{$SELF_STEAL_DOMAIN} {
    bind 0.0.0.0
    redir https://{$SELF_STEAL_DOMAIN}{uri} permanent
}

https://{$SELF_STEAL_DOMAIN} {
    root * /var/www/html
    try_files {path} /index.html
    file_server
}

:{$SELF_STEAL_PORT} {
    tls internal
    respond 204
}

:80 {
    bind 0.0.0.0
    respond 204
}
EOF

    echo "--------------------------------------------------------"
    read -p "Введите домен для SELF_STEAL_DOMAIN (например, example.com): " USER_DOMAIN

    echo "Создание файла .env..."
    cat << EOF > .env
SELF_STEAL_DOMAIN=$USER_DOMAIN
SELF_STEAL_PORT=9443
EOF

    echo "Создание docker-compose.yml для selfsteel..."
    cat << 'EOF' > docker-compose.yml
services:
  caddy:
    image: caddy:latest
    container_name: caddy-remnawave
    restart: unless-stopped
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - ../html:/var/www/html
      - ./logs:/var/log/caddy
      - caddy_data_selfsteal:/data
      - caddy_config_selfsteal:/config
    env_file:
      - .env
    network_mode: "host"

volumes:
  caddy_data_selfsteal:
  caddy_config_selfsteal:
EOF

    echo -e "${GREEN}Запуск selfsteel...${NC}"
    docker compose up -d

    echo -e "${GREEN}Создание тестовой HTML страницы (заглушки)...${NC}"
    mkdir -p /opt/html
    printf '%s\n' '<!doctype html><meta charset="utf-8"><title>Selfsteal</title><h1>It works.</h1>' > /opt/html/index.html
else
    echo "Пропуск настройки selfsteel."
fi
echo ""

# --- 4. Настройка UFW ---
if ask_yes_no "Настроить файрвол UFW (SSH, 80, 443, 2222, 9100)?"; then
    echo -e "${GREEN}Настройка UFW...${NC}"
    ufw allow 22/tcp
    ufw allow 80/tcp
    ufw allow 443
    ufw allow 2222
    ufw allow from 87.121.89.33 to any port 9100 proto tcp
    ufw --force enable
    echo "UFW успешно настроен и активирован."
else
    echo "Пропуск настройки UFW."
fi
echo ""

# --- 5. Настройка Fail2Ban ---
if ask_yes_no "Установить и настроить Fail2Ban для защиты от брутфорса?"; then
    echo -e "${GREEN}Установка Fail2Ban...${NC}"
    apt update -q
    apt install fail2ban -y -q

    echo "Запись конфигурации в /etc/fail2ban/jail.local..."
    cat << 'EOF' > /etc/fail2ban/jail.local
[INCLUDES]
before = paths-debian.conf

[DEFAULT]
ignorecommand =
bantime  = 10m
findtime  = 10m
maxretry = 5
maxmatches = %(maxretry)s
backend = auto
usedns = warn
logencoding = auto
enabled = false
mode = normal
filter = %(__name__)s[mode=%(mode)s]
destemail = root@localhost
sender = root@<fq-hostname>
mta = sendmail
protocol = tcp
chain = <known/chain>
port = 0:65535
fail2ban_agent = Fail2Ban/%(fail2ban_version)s
banaction = iptables-multiport
banaction_allports = iptables-allports
action_ = %(banaction)s[port="%(port)s", protocol="%(protocol)s", chain="%(chain)s"]
action_mw = %(action_)s
            %(mta)s-whois[sender="%(sender)s", dest="%(destemail)s", protocol="%(protocol)s", chain="%(chain)s"]
action_mwl = %(action_)s
             %(mta)s-whois-lines[sender="%(sender)s", dest="%(destemail)s", logpath="%(logpath)s", chain="%(chain)s"]
action_xarf = %(action_)s
             xarf-login-attack[service=%(__name__)s, sender="%(sender)s", logpath="%(logpath)s", port="%(port)s"]
action_cf_mwl = cloudflare[cfuser="%(cfemail)s", cftoken="%(cfapikey)s"]
                %(mta)s-whois-lines[sender="%(sender)s", dest="%(destemail)s", logpath="%(logpath)s", chain="%(chain)s"]
action_blocklist_de  = blocklist_de[email="%(sender)s", service="%(__name__)s", apikey="%(blocklist_de_apikey)s", agent="%(fail2ban_agent)s"]
action_abuseipdb = abuseipdb
action = %(action_)s

[sshd]
enabled = true
port    = ssh
filter  = sshd
logpath = %(sshd_log)s
maxretry = 3
bantime  = 999h
findtime = 10m

[dropbear]
port     = ssh
logpath  = %(dropbear_log)s
backend  = %(dropbear_backend)s

[apache-badbots]
port     = http,https
logpath  = %(apache_access_log)s
bantime  = 48h
maxretry = 1

[nginx-http-auth]
port    = http,https
logpath = %(nginx_error_log)s

[recidive]
logpath  = /var/log/fail2ban.log
banaction = %(banaction_allports)s
bantime  = 1w
findtime = 1d
EOF

    echo "Перезапуск Fail2Ban..."
    systemctl restart fail2ban
    echo "Fail2Ban успешно настроен."
else
    echo "Пропуск настройки Fail2Ban."
fi
echo ""

# --- 6. Настройка Node Exporter ---
if ask_yes_no "Установить Node Exporter для сбора метрик в VictoriaMetrics/Grafana?"; then
    echo -e "${GREEN}Установка Node Exporter (через Docker)...${NC}"
    
    # Проверяем, не запущен ли уже контейнер с таким именем
    if [ "$(docker ps -q -f name=node-exporter)" ]; then
        echo "Контейнер node-exporter уже запущен."
    else
        docker run -d \
          --name node-exporter \
          --restart unless-stopped \
          -p 9100:9100 \
          --net="host" \
          --pid="host" \
          -v "/:/host:ro,rslave" \
          prom/node-exporter \
          --path.rootfs=/host
        echo "Node Exporter успешно запущен на порту 9100."
    fi
else
    echo "Пропуск установки Node Exporter."
fi
echo ""

echo -e "${GREEN}=================================================================${NC}"
echo -e "${GREEN}Установка завершена!${NC}"
echo -e "Чтобы посмотреть логи контейнеров в реальном времени, выполни:"
echo -e "  Для remnanode: ${YELLOW}cd /opt/remnanode && docker compose logs -f -t${NC}"
echo -e "  Для selfsteel: ${YELLOW}cd /opt/selfsteel && docker compose logs -f -t${NC}"
echo -e "${GREEN}=================================================================${NC}"