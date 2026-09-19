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

usage() {
  cat >&2 <<EOF
Uso:
  import.sh push [archivo.json]   Sube todos los workflows locales (o uno solo) a n8n.
                                   Si el nombre del archivo trae _<id>.json, actualiza (PUT);
                                   si no trae id, crea uno nuevo (POST) y renombra el archivo.
  import.sh delete <archivo.json|id>
                                   Borra un workflow puntual en n8n (pide confirmación).
                                   Nunca borra por ausencia de archivo: hay que invocarlo a propósito.
EOF
  exit 1
}

# Extrae el id del nombre de archivo <nombre>_<id>.json (id alfanumérico de n8n)
extract_id() {
  local fname="$1"
  local base
  base=$(basename "$fname" .json)
  if [[ "$base" =~ _([A-Za-z0-9]{10,25})$ ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    echo ""
  fi
}

# Payload seguro para la API: solo los campos que n8n acepta en create/update
build_payload() {
  local file="$1"
  jq '{name, nodes, connections, settings, staticData, pinData} | with_entries(select(.value != null))' "$file"
}

push_one() {
  local file="$1"
  local id payload response resp_id dir base new_name

  id=$(extract_id "$file")
  payload=$(build_payload "$file")

  if [[ -n "$id" ]]; then
    echo "Actualizando ($id): $file"
    response=$(curl -sS -X PUT \
      -H "X-N8N-API-KEY: $N8N_API_KEY" \
      -H "Content-Type: application/json" \
      -d "$payload" \
      "$N8N_URL/api/v1/workflows/$id")
  else
    echo "Creando (sin id previo): $file"
    response=$(curl -sS -X POST \
      -H "X-N8N-API-KEY: $N8N_API_KEY" \
      -H "Content-Type: application/json" \
      -d "$payload" \
      "$N8N_URL/api/v1/workflows")
  fi

  resp_id=$(echo "$response" | jq -r '.id // empty')
  if [[ -z "$resp_id" ]]; then
    echo "  Error subiendo $file:" >&2
    echo "$response" | jq . >&2 2>/dev/null || echo "$response" >&2
    return 1
  fi

  # Reescribe el archivo con la respuesta completa de n8n (mismas keys ordenadas que export.sh)
  if [[ -z "$id" ]]; then
    dir=$(dirname "$file")
    base=$(basename "$file" .json)
    new_name="$dir/${base}_${resp_id}.json"
    echo "$response" | jq -S '.' > "$new_name"
    rm -f "$file"
    echo "  Creado con id $resp_id -> $new_name"
  else
    echo "$response" | jq -S '.' > "$file"
    echo "  Actualizado."
  fi
}

cmd_push() {
  if [[ $# -eq 1 ]]; then
    push_one "$1"
    return
  fi

  find "$WORKFLOWS_DIR" -type f -name '*.json' | while read -r f; do
    push_one "$f" || true
  done
}

cmd_delete() {
  local arg="$1"
  local id file_to_remove=""

  if [[ -f "$arg" ]]; then
    id=$(extract_id "$arg")
    file_to_remove="$arg"
    if [[ -z "$id" ]]; then
      echo "Error: $arg no tiene un id de n8n en el nombre (nunca se subió)." >&2
      exit 1
    fi
  else
    id="$arg"
  fi

  echo "Vas a BORRAR el workflow con id '$id' en $N8N_URL. Esta acción es irreversible."
  read -r -p "Confirmar borrado? (escribe 'si' para continuar): " confirm
  if [[ "$confirm" != "si" ]]; then
    echo "Cancelado."
    exit 0
  fi

  http_code=$(curl -sS -o /tmp/n8n_delete_resp.json -w '%{http_code}' -X DELETE \
    -H "X-N8N-API-KEY: $N8N_API_KEY" \
    "$N8N_URL/api/v1/workflows/$id")

  if [[ "$http_code" != "200" ]]; then
    echo "Error borrando $id (HTTP $http_code):" >&2
    cat /tmp/n8n_delete_resp.json >&2
    exit 1
  fi

  echo "Workflow $id borrado en n8n."

  if [[ -n "$file_to_remove" ]]; then
    git rm -f "$file_to_remove" >/dev/null
    echo "Archivo local eliminado y quitado de git: $file_to_remove"
    echo "Recuerda hacer commit: git commit -m 'chore: eliminar workflow $id'"
  fi
}

[[ $# -lt 1 ]] && usage

case "$1" in
  push)
    shift
    cmd_push "$@"
    ;;
  delete)
    shift
    [[ $# -eq 1 ]] || usage
    cmd_delete "$1"
    ;;
  *)
    usage
    ;;
esac
