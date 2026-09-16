#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

CONFIG_FILE="config.yaml"
WORKFLOWS_DIR="workflows"

N8N_API_KEY=$(awk -F': ' '/^n8n_api:/{print $2}' "$CONFIG_FILE")
N8N_URL=$(awk -F': ' '/^n8n_url:/{print $2}' "$CONFIG_FILE" | sed 's:/*$::')

if [[ -z "$N8N_API_KEY" || -z "$N8N_URL" ]]; then
  echo "Error: falta n8n_api o n8n_url en $CONFIG_FILE" >&2
  exit 1
fi

mkdir -p "$WORKFLOWS_DIR"

echo "Listando workflows desde $N8N_URL ..."

cursor=""
ids_names=""
while : ; do
  url="$N8N_URL/api/v1/workflows?limit=100"
  if [[ -n "$cursor" ]]; then
    url="${url}&cursor=${cursor}"
  fi

  response=$(curl -sS -H "X-N8N-API-KEY: $N8N_API_KEY" "$url")

  page_ids_names=$(echo "$response" | jq -r '.data[] | "\(.id)\t\(.name)"')
  if [[ -n "$page_ids_names" ]]; then
    ids_names="${ids_names}${page_ids_names}"$'\n'
  fi

  cursor=$(echo "$response" | jq -r '.nextCursor // empty')
  if [[ -z "$cursor" ]]; then
    break
  fi
done

if [[ -z "$ids_names" ]]; then
  echo "No se encontraron workflows (o la API no respondió datos)." >&2
  exit 1
fi

tmp_ids_file=$(mktemp)
echo "$ids_names" > "$tmp_ids_file"

while IFS=$'\t' read -r id name; do
  [[ -z "$id" ]] && continue

  if [[ "$name" =~ ^S([0-9]+)- ]]; then
    subdir="Semana ${BASH_REMATCH[1]}"
  elif [[ "$name" =~ ^Taller ]]; then
    subdir="Taller"
  else
    subdir="Otros"
  fi
  mkdir -p "$WORKFLOWS_DIR/$subdir"

  safe_name=$(echo "$name" | tr '/\\:*?"<>|' '_' | tr -s ' ' '_')
  outfile="$WORKFLOWS_DIR/$subdir/${safe_name}_${id}.json"
  tmp_file=$(mktemp)

  curl -sS -H "X-N8N-API-KEY: $N8N_API_KEY" \
    "$N8N_URL/api/v1/workflows/$id" -o "$tmp_file"
  jq -S '.' "$tmp_file" > "$outfile"
  rm -f "$tmp_file"

  echo "Exportado: $outfile"
done < "$tmp_ids_file"

rm -f "$tmp_ids_file"

echo "Revisando cambios en git..."
git add "$WORKFLOWS_DIR"

if git diff --cached --quiet -- "$WORKFLOWS_DIR"; then
  echo "Sin cambios reales en los workflows. No se crea commit."
  exit 0
fi

commit_msg="Backup workflows n8n - $(date '+%Y-%m-%d %H:%M:%S')"
git commit -m "$commit_msg

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
git push origin main

echo "Cambios commiteados y subidos a GitHub."
