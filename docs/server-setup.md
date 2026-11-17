# Конфигурация виртуальной машины devops-vm

Студент: Бакиев Р. А., группа ЭФБО-09-24.

## 1. Параметры машины

| Параметр | Значение |
|---|---|
| Средство виртуализации | WSL 2 (Hyper-V) на Windows 11; экземпляр `devops-vm-bakiev` |
| Гостевая ОС | Ubuntu 24.04.5 LTS (Server, без графической подсистемы) |
| Имя узла | `devops-vm` (FQDN `devops-vm.devops.local`) |
| Оперативная память | до 15,3 ГБ (динамически, общий лимит WSL 2) |
| Процессор | 14 логических ядер (общий пул WSL 2) |
| Диск | виртуальный диск VHDX, динамически расширяемый (до 1 ТБ) |

Создание экземпляра (PowerShell на хосте):

```powershell
wsl --install -d Ubuntu-24.04 --name devops-vm-bakiev --no-launch
```

Первичная настройка от root (`wsl -d devops-vm-bakiev -u root`):

```bash
cat > /etc/wsl.conf <<'EOF'
[boot]
systemd=true
[network]
hostname=devops-vm
generateHosts=false
[user]
default=student
EOF
useradd -m -s /bin/bash -G sudo student && passwd student
apt update && apt install -y openssh-server ufw && apt upgrade -y
```

После этого: `wsl --terminate devops-vm-bakiev` и повторный запуск (включается systemd и имя узла).

## 2. Сетевые интерфейсы

| Интерфейс | Тип | Адрес | Назначение |
|---|---|---|---|
| `eth0` | виртуальная сеть WSL (NAT) | `172.19.233.223/20`, хост в этой сети — `172.19.224.1` | выход в Интернет (аналог адаптера NAT) и прямой доступ с хоста по адресу (аналог Host-only) |
| `lo` | обратная петля | `127.0.0.1` | локальные службы |

Адрес назначается при запуске WSL и может измениться после перезагрузки хоста — проверяется командой `ip -brief address`.

## 3. Правило проброса портов

| Порт хостовой системы | Порт гостевой системы | Механизм |
|---|---|---|
| `127.0.0.1:2222` | `2222` | автоматическая переадресация localhost WSL 2 (`localhostForwarding`) |

В WSL 2 порт, прослушиваемый в гостевой системе, автоматически доступен на `127.0.0.1` хоста под тем же номером. До смены порта SSH подключение выполнялось к `127.0.0.1:22`.

## 4. Учётные записи

| Имя | Группы | Аутентификация |
|---|---|---|
| `student` | `student`, `sudo` | вход по SSH запрещён (`AllowUsers devops`); используется только в консоли `wsl -d devops-vm-bakiev` |
| `devops` | `devops`, `sudo`, `users` | только по ключу ed25519 `~/.ssh/devops_vm` (комментарий `devops-vm-key`) |

```bash
sudo adduser devops
sudo usermod -aG sudo devops
# на хосте:
ssh-keygen -t ed25519 -C "devops-vm-key" -f ~/.ssh/devops_vm
# в консоли ВМ от имени devops (открытый ключ скопирован с хоста):
mkdir -p ~/.ssh && chmod 700 ~/.ssh
cat devops_vm.pub >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys
```

Файл `~/.ssh/config` на хосте:

```
Host devops
    HostName 127.0.0.1
    Port 2222
    User devops
    IdentityFile ~/.ssh/devops_vm
    IdentitiesOnly yes
```

Особенность стенда: для записи вывода команд без интерактивного ввода в `/etc/sudoers.d/90-stand` (создан через `visudo -cf`) пользователям `student` и `devops` разрешён `sudo` без пароля.

## 5. Служба SSH

Основной файл `/etc/ssh/sshd_config` не изменялся (копия — `/etc/ssh/sshd_config.backup`). Дополняющий файл `/etc/ssh/sshd_config.d/99-hardening.conf`:

```
Port 2222
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
AllowUsers devops
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
```

Активация по сокету отключена, служба запускается напрямую:

```bash
sudo sshd -t
sudo systemctl disable --now ssh.socket
sudo systemctl enable --now ssh.service
sudo systemctl restart ssh
sudo ss -tlnp | grep sshd      # 0.0.0.0:2222
```

## 6. Правила межсетевого экрана

Политики: `deny (incoming)`, `allow (outgoing)`, `disabled (routed)`; журналирование `medium`.

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw limit 2222/tcp comment 'SSH rate-limited'
sudo ufw allow 80/tcp  comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw enable
sudo ufw logging medium
```

| Порт | Действие | Назначение |
|---|---|---|
| 2222/tcp | LIMIT | SSH |
| 80/tcp | ALLOW | HTTP |
| 443/tcp | ALLOW | HTTPS |

Имя: в `C:\Windows\System32\drivers\etc\hosts` хоста — `172.19.233.223 devops.local`; на сервере в `/etc/hosts` — `127.0.1.1 devops-vm.devops.local devops-vm`.

## 7. Снимки состояния

Менеджер снимков VirtualBox в WSL отсутствует; снимок — экспорт файловой системы экземпляра в архив (`wsl --export`), откат — `wsl --unregister devops-vm-bakiev` и `wsl --import devops-vm-bakiev <каталог> <архив>`.

| Снимок | Момент создания | Файл |
|---|---|---|
| `01-clean-install` | 2026-11-17 19:21, после установки ОС | `C:\WSL-snapshots\bakiev\01-clean-install.tar` |
| `02-keys-configured` | 2026-11-17 19:22, после настройки ключевого входа | `C:\WSL-snapshots\bakiev\02-keys-configured.tar` |
| `03-ssh-hardened` | 2026-11-17 19:23, после усиления SSH | `C:\WSL-snapshots\bakiev\03-ssh-hardened.tar` |

## 8. Веб-сервер

| Параметр | Значение |
|---|---|
| Пакет | `nginx` 1.24.0 из репозитория Ubuntu (`sudo apt install -y nginx`) |
| Конфигурация ресурса | `/etc/nginx/sites-available/devops-site`, ссылка `/etc/nginx/sites-enabled/devops-site`; ссылка `sites-enabled/default` удалена |
| Каталог ресурса | `/var/www/devops-site`, владелец `devops:devops`, каталог `755`, файлы `644` |
| Сертификат | `/etc/ssl/certs/devops.crt`, `root:root`, `644`, срок 365 дней, SAN `DNS:devops.local` |
| Закрытый ключ | `/etc/ssl/private/devops.key`, `root:root`, `600` |
| Журналы | `/var/log/nginx/devops-site.access.log`, `/var/log/nginx/devops-site.error.log` |

```bash
sudo apt update && sudo apt install -y nginx
sudo mkdir -p /var/www/devops-site && sudo chown -R devops:devops /var/www/devops-site
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/devops.key -out /etc/ssl/certs/devops.crt \
  -subj "/CN=devops.local" -addext "subjectAltName=DNS:devops.local"
sudo ln -s /etc/nginx/sites-available/devops-site /etc/nginx/sites-enabled/
sudo rm /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx
```

Текст `/etc/nginx/sites-available/devops-site`:

```nginx
server {
    listen 80;
    listen [::]:80;
    server_name devops.local;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name devops.local;
    ssl_certificate     /etc/ssl/certs/devops.crt;
    ssl_certificate_key /etc/ssl/private/devops.key;
    ssl_protocols       TLSv1.2 TLSv1.3;

    root /var/www/devops-site;
    index index.html;
    location / {
        try_files $uri $uri/ =404;
    }
    error_page 404 /404.html;
    access_log /var/log/nginx/devops-site.access.log;
    error_log  /var/log/nginx/devops-site.error.log;
}
```

Содержимое доставляется с хоста сценарием `scripts/deploy.sh` (rsync с `--delete --chmod=D755,F644`). На хосте (Git Bash) rsync 3.4.4 установлен из пакетов MSYS2 в `~/bin`; сертификат для проверки — `~/devops.crt` (`scp devops:/etc/ssl/certs/devops.crt ~/devops.crt`).

## 9. Контейнеризация

| Параметр | Значение |
|---|---|
| Docker Engine | 29.10.0 из официального репозитория `download.docker.com` (пакеты `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, `docker-compose-plugin`); `docker.io` не используется |
| Compose | плагин `docker compose` v5.8.0 |
| Участники группы `docker` | `devops` (имеет право sudo; группа `docker` равнозначна root) |
| DNS контейнеров | `/etc/docker/daemon.json`: `{"dns": ["1.1.1.1", "8.8.8.8"]}` (особенность стенда: резолвер WSL недоступен из сетей Docker) |
| Проект | `~/app` на сервере (доставка: `rsync -avz --delete --exclude=.env app/ devops:app/`) |
| Секреты | `~/app/.env`, владелец `devops`, права `600`; создаётся только на сервере из `.env.example` |
| Публикуемые порты | `127.0.0.1:5000` → `app:5000`; порт СУБД 5432 не публикуется |
| Тома | `app_db_data` → `/var/lib/postgresql/data` |
| Сеть | `app_backend` (bridge), имена сервисов `app`, `db` |

```bash
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker devops      # затем новая SSH-сессия

cd ~/app
cp .env.example .env && chmod 600 .env
sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$(openssl rand -hex 16)/" .env
docker compose up -d --build
```

Обратный прокси — в блоке HTTPS `/etc/nginx/sites-available/devops-site` после `error_page`:

```nginx
    location /app/ {
        proxy_pass http://127.0.0.1:5000/;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
```

Снимок `05-docker-compose` — 2026-11-17 20:09, `C:\WSL-snapshots\bakiev\05-docker-compose.tar`; снимок `04-nginx-https` — 2026-11-17 19:43.
