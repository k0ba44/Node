#!/bin/bash

# Остановка скрипта при ошибке
set -e

echo "=== Установка Docker ==="
curl -fsSL https://get.docker.com | sh

echo "=== Настройка /opt/remnanode ==="
mkdir -p /opt/remnanode
cd /opt/remnanode

echo "--------------------------------------------------------"
echo "Сейчас откроется редактор nano для docker-compose.yml."
echo "Вставь нужный код, сохрани (Ctrl+O -> Enter) и выйди (Ctrl+X)."
echo "--------------------------------------------------------"
read -p "Нажми Enter, чтобы открыть редактор..."
nano docker-compose.yml

echo "Запуск remnanode..."
docker compose up -d

echo "=== Настройка /opt/selfsteel ==="
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

echo "Запуск selfsteel..."
docker compose up -d

echo "=== Создание тестовой страницы HTML ==="
mkdir -p /opt/html
printf '%s\n' '<!doctype html><meta charset="utf-8"><title>Selfsteal</title><h1>It works.</h1>' > /opt/html/index.html

echo "=== Настройка UFW ==="
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443
ufw allow 2222
ufw allow from 87.121.89.33 to any port 9100 proto tcp
ufw --force enable

echo "=== Настройка Fail2Ban ==="
apt install fail2ban -y

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

[selinux-ssh]
port     = ssh
logpath  = %(auditd_log)s

[apache-auth]
port     = http,https
logpath  = %(apache_error_log)s

[apache-badbots]
port     = http,https
logpath  = %(apache_access_log)s
bantime  = 48h
maxretry = 1

[apache-noscript]
port     = http,https
logpath  = %(apache_error_log)s

[apache-overflows]
port     = http,https
logpath  = %(apache_error_log)s
maxretry = 2

[apache-nohome]
port     = http,https
logpath  = %(apache_error_log)s
maxretry = 2

[apache-botsearch]
port     = http,https
logpath  = %(apache_error_log)s
maxretry = 2

[apache-fakegooglebot]
port     = http,https
logpath  = %(apache_access_log)s
maxretry = 1
ignorecommand = %(fail2ban_confpath)s/filter.d/ignorecommands/apache-fakegooglebot <ip>

[apache-modsecurity]
port     = http,https
logpath  = %(apache_error_log)s
maxretry = 2

[apache-shellshock]
port    = http,https
logpath = %(apache_error_log)s
maxretry = 1

[openhab-auth]
filter = openhab
banaction = %(banaction_allports)s
logpath = /opt/openhab/logs/request.log

[nginx-http-auth]
port    = http,https
logpath = %(nginx_error_log)s

[nginx-limit-req]
port    = http,https
logpath = %(nginx_error_log)s

[nginx-botsearch]
port     = http,https
logpath  = %(nginx_error_log)s

[nginx-bad-request]
port    = http,https
logpath = %(nginx_access_log)s

[php-url-fopen]
port    = http,https
logpath = %(nginx_access_log)s
          %(apache_access_log)s

[suhosin]
port    = http,https
logpath = %(suhosin_log)s

[lighttpd-auth]
port    = http,https
logpath = %(lighttpd_error_log)s

[roundcube-auth]
port     = http,https
logpath  = %(roundcube_errors_log)s

[openwebmail]
port     = http,https
logpath  = /var/log/openwebmail.log

[horde]
port     = http,https
logpath  = /var/log/horde/horde.log

[groupoffice]
port     = http,https
logpath  = /home/groupoffice/log/info.log

[sogo-auth]
port     = http,https
logpath  = /var/log/sogo/sogo.log

[tine20]
logpath  = /var/log/tine20/tine20.log
port     = http,https

[drupal-auth]
port     = http,https
logpath  = %(syslog_daemon)s
backend  = %(syslog_backend)s

[guacamole]
port     = http,https
logpath  = /var/log/tomcat*/catalina.out

[monit]
port = 2812
logpath  = /var/log/monit
           /var/log/monit.log

[webmin-auth]
port    = 10000
logpath = %(syslog_authpriv)s
backend = %(syslog_backend)s

[froxlor-auth]
port    = http,https
logpath  = %(syslog_authpriv)s
backend  = %(syslog_backend)s

[squid]
port     =  80,443,3128,8080
logpath = /var/log/squid/access.log

[3proxy]
port    = 3128
logpath = /var/log/3proxy.log

[proftpd]
port     = ftp,ftp-data,ftps,ftps-data
logpath  = %(proftpd_log)s
backend  = %(proftpd_backend)s

[pure-ftpd]
port     = ftp,ftp-data,ftps,ftps-data
logpath  = %(pureftpd_log)s
backend  = %(pureftpd_backend)s

[gssftpd]
port     = ftp,ftp-data,ftps,ftps-data
logpath  = %(syslog_daemon)s
backend  = %(syslog_backend)s

[wuftpd]
port     = ftp,ftp-data,ftps,ftps-data
logpath  = %(wuftpd_log)s
backend  = %(wuftpd_backend)s

[vsftpd]
port     = ftp,ftp-data,ftps,ftps-data
logpath  = %(vsftpd_log)s

[assp]
port     = smtp,465,submission
logpath  = /root/path/to/assp/logs/maillog.txt

[courier-smtp]
port     = smtp,465,submission
logpath  = %(syslog_mail)s
backend  = %(syslog_backend)s

[postfix]
mode    = more
port    = smtp,465,submission
logpath = %(postfix_log)s
backend = %(postfix_backend)s

[postfix-rbl]
filter   = postfix[mode=rbl]
port     = smtp,465,submission
logpath  = %(postfix_log)s
backend  = %(postfix_backend)s
maxretry = 1

[sendmail-auth]
port    = submission,465,smtp
logpath = %(syslog_mail)s
backend = %(syslog_backend)s

[sendmail-reject]
port     = smtp,465,submission
logpath  = %(syslog_mail)s
backend  = %(syslog_backend)s

[qmail-rbl]
filter  = qmail
port    = smtp,465,submission
logpath = /service/qmail/log/main/current

[dovecot]
port    = pop3,pop3s,imap,imaps,submission,465,sieve
logpath = %(dovecot_log)s
backend = %(dovecot_backend)s

[sieve]
port   = smtp,465,submission
logpath = %(dovecot_log)s
backend = %(dovecot_backend)s

[solid-pop3d]
port    = pop3,pop3s
logpath = %(solidpop3d_log)s

[exim]
port   = smtp,465,submission
logpath = %(exim_main_log)s

[exim-spam]
port   = smtp,465,submission
logpath = %(exim_main_log)s

[kerio]
port    = imap,smtp,imaps,465
logpath = /opt/kerio/mailserver/store/logs/security.log

[courier-auth]
port     = smtp,465,submission,imap,imaps,pop3,pop3s
logpath  = %(syslog_mail)s
backend  = %(syslog_backend)s

[postfix-sasl]
filter   = postfix[mode=auth]
port     = smtp,465,submission,imap,imaps,pop3,pop3s
logpath  = %(postfix_log)s
backend  = %(postfix_backend)s

[perdition]
port   = imap,imaps,pop3,pop3s
logpath = %(syslog_mail)s
backend = %(syslog_backend)s

[squirrelmail]
port = smtp,465,submission,imap,imap2,imaps,pop3,pop3s,http,https,socks
logpath = /var/lib/squirrelmail/prefs/squirrelmail_access_log

[cyrus-imap]
port   = imap,imaps
logpath = %(syslog_mail)s
backend = %(syslog_backend)s

[uwimap-auth]
port   = imap,imaps
logpath = %(syslog_mail)s
backend = %(syslog_backend)s

[named-refused]
port     = domain,953
logpath  = /var/log/named/security.log

[nsd]
port     = 53
action_  = %(default/action_)s[name=%(__name__)s-tcp, protocol="tcp"]
           %(default/action_)s[name=%(__name__)s-udp, protocol="udp"]
logpath = /var/log/nsd.log

[asterisk]
port     = 5060,5061
action_  = %(default/action_)s[name=%(__name__)s-tcp, protocol="tcp"]
           %(default/action_)s[name=%(__name__)s-udp, protocol="udp"]
logpath  = /var/log/asterisk/messages
maxretry = 10

[freeswitch]
port     = 5060,5061
action_  = %(default/action_)s[name=%(__name__)s-tcp, protocol="tcp"]
           %(default/action_)s[name=%(__name__)s-udp, protocol="udp"]
logpath  = /var/log/freeswitch.log
maxretry = 10

[znc-adminlog]
port     = 6667
logpath  = /var/lib/znc/moddata/adminlog/znc.log

[mysqld-auth]
port     = 3306
logpath  = %(mysql_log)s
backend  = %(mysql_backend)s

[mssql-auth]
logpath = /var/opt/mssql/log/errorlog
port = 1433
filter = mssql-auth

[mongodb-auth]
port     = 27017
logpath  = /var/log/mongodb/mongodb.log

[recidive]
logpath  = /var/log/fail2ban.log
banaction = %(banaction_allports)s
bantime  = 1w
findtime = 1d

[pam-generic]
banaction = %(banaction_allports)s
logpath  = %(syslog_authpriv)s
backend  = %(syslog_backend)s

[xinetd-fail]
banaction = iptables-multiport-log
logpath   = %(syslog_daemon)s
backend   = %(syslog_backend)s
maxretry  = 2

[stunnel]
logpath = /var/log/stunnel4/stunnel.log

[ejabberd-auth]
port    = 5222
logpath = /var/log/ejabberd/ejabberd.log

[counter-strike]
logpath = /opt/cstrike/logs/L[0-9]*.log
tcpport = 27030,27031,27032,27033,27034,27035,27036,27037,27038,27039
udpport = 1200,27000,27001,27002,27003,27004,27005,27006,27007,27008,27009,27010,27011,27012,27013,27014,27015
action_  = %(default/action_)s[name=%(__name__)s-tcp, port="%(tcpport)s", protocol="tcp"]
           %(default/action_)s[name=%(__name__)s-udp, port="%(udpport)s", protocol="udp"]

[softethervpn]
port     = 500,4500
protocol = udp
logpath  = /usr/local/vpnserver/security_log/*/sec.log

[gitlab]
port    = http,https
logpath = /var/log/gitlab/gitlab-rails/application.log

[grafana]
port    = http,https
logpath = /var/log/grafana/grafana.log

[bitwarden]
port    = http,https
logpath = /home/*/bwdata/logs/identity/Identity/log.txt

[centreon]
port    = http,https
logpath = /var/log/centreon/login.log

[nagios]
logpath  = %(syslog_daemon)s
backend  = %(syslog_backend)s
maxretry = 1

[oracleims]
logpath = /opt/sun/comms/messaging64/log/mail.log_current
banaction = %(banaction_allports)s

[directadmin]
logpath = /var/log/directadmin/login.log
port = 2222

[portsentry]
logpath  = /var/lib/portsentry/portsentry.history
maxretry = 1

[pass2allow-ftp]
port         = ftp,ftp-data,ftps,ftps-data
knocking_url = /knocking/
filter       = apache-pass[knocking_url="%(knocking_url)s"]
logpath      = %(apache_access_log)s
blocktype    = RETURN
returntype   = DROP
action       = %(action_)s[blocktype=%(blocktype)s, returntype=%(returntype)s,
                        actionstart_on_demand=false, actionrepair_on_unban=true]
bantime      = 1h
maxretry     = 1
findtime     = 1

[murmur]
port     = 64738
action_  = %(default/action_)s[name=%(__name__)s-tcp, protocol="tcp"]
           %(default/action_)s[name=%(__name__)s-udp, protocol="udp"]
logpath  = /var/log/mumble-server/mumble-server.log

[screensharingd]
logpath  = /var/log/system.log
logencoding = utf-8

[haproxy-http-auth]
logpath  = /var/log/haproxy.log

[slapd]
port    = ldap,ldaps
logpath = /var/log/slapd.log

[domino-smtp]
port    = smtp,ssmtp
logpath = /home/domino01/data/IBM_TECHNICAL_SUPPORT/console.log

[phpmyadmin-syslog]
port    = http,https
logpath = %(syslog_authpriv)s
backend = %(syslog_backend)s

[zoneminder]
port    = http,https
logpath = %(apache_error_log)s

[traefik-auth]
port    = http,https
logpath = /var/log/traefik/access.log

[scanlogd]
logpath = %(syslog_local0)s
banaction = %(banaction_allports)s

[monitorix]
port	= 8080
logpath = /var/log/monitorix-httpd
EOF

echo "Перезапуск Fail2Ban..."
systemctl restart fail2ban

echo "=== Установка Node Exporter (Grafana) ==="
docker run -d \
  --name node-exporter \
  --restart unless-stopped \
  -p 9100:9100 \
  --net="host" \
  --pid="host" \
  -v "/:/host:ro,rslave" \
  prom/node-exporter \
  --path.rootfs=/host

echo "================================================================="
echo "Установка успешно завершена!"
echo "Конфигурация Fail2Ban (jail.local) успешно применена."
echo "Чтобы посмотреть логи контейнеров в реальном времени, выполни:"
echo "  Для remnanode: cd /opt/remnanode && docker compose logs -f -t"
echo "  Для selfsteel: cd /opt/selfsteel && docker compose logs -f -t"
echo "================================================================="
