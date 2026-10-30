#!/usr/bin/env bash
# Собирает списки из iplist (https://github.com/rekryt/iplist) под выбранные группы
# и кладёт их в release/ в форматах для Xray/Happ (.dat), Mihomo/Clash/Stash (.yaml) и sing-box (.json).
set -euo pipefail
cd "$(dirname "$0")"

BASE="${IPLIST_URL:-https://iplist.opencck.org}"
mkdir -p release

SEL_GROUPS=()
QUERY=""
while IFS= read -r line || [ -n "$line" ]; do
  line="${line%%#*}"
  line="$(printf '%s' "$line" | tr -d '[:space:]')"
  [ -z "$line" ] && continue
  if ! printf '%s' "$line" | grep -Eq '^[a-z0-9._-]+$'; then
    echo "ERROR: странное имя группы: $line" >&2; exit 1
  fi
  SEL_GROUPS+=("$line")
  QUERY+="&group=$line"
done < groups.txt

if [ "${#SEL_GROUPS[@]}" -eq 0 ]; then
  echo "ERROR: groups.txt пуст — нужна хотя бы одна группа" >&2; exit 1
fi
echo "Группы: ${SEL_GROUPS[*]}"

# fetch <имя файла> <параметры запроса> <минимальный размер в байтах>
fetch() {
  local name="$1" params="$2" min="$3" tmp="release/.$1.tmp"
  curl -fsSL --retry 4 --retry-delay 10 --max-time 240 -o "$tmp" "$BASE/?$params$QUERY"
  local size; size="$(stat -c %s "$tmp")"
  if [ "$size" -lt "$min" ]; then
    echo "ERROR: $name слишком маленький ($size байт, ждали >= $min). Начало ответа:" >&2
    head -c 300 "$tmp" >&2; echo >&2; rm -f "$tmp"; exit 1
  fi
  # iplist при ошибке отдаёт текст, начинающийся с «# Error»
  if head -c 8 "$tmp" | grep -q '^# Error'; then
    echo "ERROR: iplist вернул ошибку для $name:" >&2; head -c 300 "$tmp" >&2; echo >&2; rm -f "$tmp"; exit 1
  fi
  mv "$tmp" "release/$name"
  echo "OK $name ($size байт)"
}

# clashx-текст -> yaml с payload (понимают Mihomo, Clash, Stash)
to_yaml() {
  { echo "payload:"; tr -d '\r' < "$1" | sed -e '/^[[:space:]]*$/d' -e "s/^/  - '/" -e "s/\$/'/"; } > "$2"
  echo "OK $(basename "$2") ($(grep -c "^  - " "$2") правил)"
}

# 1) Xray / Happ / v2rayTun
fetch geosite.dat "format=geosite&data=domains" 2000
fetch geoip.dat   "format=geoip&data=cidr4"     500

# 2) Mihomo / Clash / Stash (через временные txt)
fetch .vpn-domains.txt "format=clashx&data=domains" 200
fetch .vpn-ips.txt     "format=clashx&data=cidr4"   100
to_yaml release/.vpn-domains.txt release/vpn-domains.yaml
to_yaml release/.vpn-ips.txt     release/vpn-ips.yaml
rm -f release/.vpn-domains.txt release/.vpn-ips.txt

# 3) sing-box (source-формат, читается sing-box >= 1.8)
fetch vpn-domains.json "format=singbox&data=domains" 200
fetch vpn-ips.json     "format=singbox&data=cidr4"   100

# Проверка JSON
python3 -c "import json,sys; [json.load(open('release/'+f)) for f in ('vpn-domains.json','vpn-ips.json')]; print('JSON ok')"

# Служебный файл: по нему видно, что обновление работает
{
  echo "groups: ${SEL_GROUPS[*]}"
  echo "source: $BASE"
} > release/info.txt
echo "Готово."
