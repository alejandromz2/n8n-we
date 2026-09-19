# Diploma - N8N Agentes IA

Backup versionado de los workflows de n8n usados en el curso/talleres de Educación Ejecutiva. Los workflows se exportan vía la API pública de n8n y se guardan como JSON en este repo, organizados por semana. También se pueden subir cambios locales de vuelta a n8n (crear, actualizar o borrar workflows) usando `import.sh`.

## Estructura

```
config.yaml       # credenciales locales (URL + API key) — NO se sube a git
export.sh          # script de exportación y backup (n8n -> local)
import.sh          # script para subir cambios locales a n8n (local -> n8n)
workflows/
  Semana 1/         # workflows con nombre "S1-..."
  Semana 2/         # workflows con nombre "S2-..."
  Semana 3/         # workflows con nombre "S3-..."
  Taller/           # workflows con nombre "Taller..."
  Otros/            # cualquier otro (se crea si aplica)
```

Cada workflow se guarda como `<nombre-normalizado>_<id>.json`, con las keys ordenadas alfabéticamente (`jq -S`) para que los diffs entre corridas sean estables y reflejen solo cambios reales.

## Requisitos

- `git`, `curl`, `jq` instalados.
- Acceso de escritura al repo remoto (`git remote -v` para confirmar `origin`).
- Una API key de n8n con permisos de lectura sobre workflows (Settings → n8n API en tu instancia).

## Configuración (`config.yaml`)

Este archivo está en `.gitignore` porque contiene el API key. Si no existe, créalo así:

```yaml
n8n_api: <tu_api_key>
n8n_url: https://tu-instancia.n8n.cloud
```

## Uso

Ejecutar desde la raíz del repo:

```bash
bash export.sh
```

El script:

1. Lee `n8n_api` y `n8n_url` de `config.yaml`.
2. Lista todos los workflows vía `GET /api/v1/workflows` (paginando con `nextCursor` si hay más de 100).
3. Descarga el detalle completo de cada uno (`GET /api/v1/workflows/{id}`).
4. Los clasifica en carpetas según el prefijo del nombre (`S1-` → `Semana 1`, `S2-` → `Semana 2`, `Taller` → `Taller`, resto → `Otros`).
5. Hace `git add workflows` y revisa con `git diff --cached --quiet` si hubo cambios reales.
6. Si no hay cambios, termina sin commitear (evita commits vacíos).
7. Si hay cambios, crea un commit con timestamp y hace `git push origin main`.

### Subir cambios locales a n8n (`import.sh`)

Ejecutar desde la raíz del repo:

```bash
bash import.sh push                    # sube todos los workflows locales
bash import.sh push workflows/Semana\ 3/S3-W2_..._id.json   # sube uno solo
bash import.sh delete workflows/Semana\ 3/archivo_id.json   # borra por archivo
bash import.sh delete <id>                                   # borra por id
```

- **push**: recorre `workflows/` (o toma un solo archivo si se lo pasas). Arma el payload solo con los campos que la API de n8n acepta en create/update (`name`, `nodes`, `connections`, `settings`, `staticData`, `pinData`).
  - Si el nombre del archivo trae `_<id>.json` al final, hace **PUT** (actualiza) el workflow existente.
  - Si no trae id, hace **POST** (crea uno nuevo) y renombra el archivo local a `<nombre>_<id-devuelto-por-n8n>.json`.
  - En ambos casos reescribe el archivo con la respuesta completa de n8n, con las keys ordenadas (`jq -S`) igual que `export.sh`, para que los diffs sean estables.
- **delete**: borra un workflow puntual en n8n (por archivo o por id) vía **DELETE**, pidiendo confirmación explícita (`si`) antes de ejecutar. Nunca borra por ausencia de archivo — hay que invocarlo a propósito. Si se le pasa un archivo, también lo quita del repo con `git rm`.

## Notas de seguridad

- Los JSON exportados incluyen referencias a credenciales (`id`, `name`) pero **nunca los valores secretos** — la API pública de n8n no los expone.
- Mantén el repo como **privado** si los workflows contienen lógica de negocio sensible, prompts internos, o nombres de credenciales que no quieras exponer.
- Nunca subas `config.yaml` (ya está en `.gitignore`; verifica antes de cada `git add .` que no aparezca en el status).

## Automatización pendiente

Actualmente el proceso es manual (corres `export.sh` cuando quieres respaldar). Opciones futuras si se necesita automatizar:

- **Cron local**: correr `export.sh` en un horario fijo en la máquina/servidor donde vive el repo.
- **Workflow de n8n**: un nodo *Schedule Trigger* + *Execute Command*/SSH que dispare el script desde la propia instancia de n8n.
