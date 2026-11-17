#!/usr/bin/env bash
# Доставка статического ресурса на devops-vm
# Использование: scripts/deploy.sh [--dry-run]
set -euo pipefail
REMOTE="devops"                     # псевдоним из ~/.ssh/config (ПР № 5, шаг 1.6)
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"
# cd + pwd: в Git для Windows rev-parse возвращает путь вида C:/..., который rsync
# принимает за адрес удалённого узла «C»; pwd даёт POSIX-путь /c/...
LOCAL_DIR="$(cd "$(git rev-parse --show-toplevel)" && pwd)/site/"

# 1. Разбор аргумента --dry-run
DRY_RUN=""
case "${1:-}" in
    "")        ;;
    --dry-run) DRY_RUN="--dry-run" ;;
    *)         echo "Использование: $0 [--dry-run]" >&2; exit 1 ;;
esac

# 2. Проверки по требованиям 4 и 5
if [[ ! -f "${LOCAL_DIR}index.html" ]]; then
    echo "Ошибка: файл site/index.html отсутствует, доставка отменена" >&2
    exit 1
fi
if [[ -n "$(git status --porcelain)" ]]; then
    echo "Ошибка: в репозитории есть незафиксированные изменения, доставка отменена:" >&2
    git status --short >&2
    exit 1
fi

# 3. Синхронизация: одно SSH-соединение, без интерактивного запроса пароля
rsync -avz --delete --chmod=D755,F644 ${DRY_RUN} \
    -e "ssh -o BatchMode=yes -o ConnectTimeout=5" \
    "${LOCAL_DIR}" "${REMOTE}:${REMOTE_DIR}/"

# 4. При --dry-run — завершение без проверки доступности
if [[ -n "${DRY_RUN}" ]]; then
    echo "Пробный запуск: состояние сервера не изменено"
    exit 0
fi

# 5. Проверка доступности с проверкой сертификата
if curl -fsS --cacert "${CA_CERT}" -o /dev/null "${SITE_URL}/"; then
    echo "Доставлен коммит $(git rev-parse --short HEAD)"
    exit 0
else
    echo "Ошибка: ресурс ${SITE_URL} недоступен после доставки" >&2
    exit 1
fi
