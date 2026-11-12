#!/usr/bin/env bash
# Calcula a próxima versão semântica a partir dos Conventional Commits desde a última tag.
#   feat!: / BREAKING CHANGE  -> major
#   feat:                     -> minor
#   fix: / perf:              -> patch
#   demais tipos              -> sem release
# Saída (formato $GITHUB_OUTPUT): released, version, tag, notes-file
set -euo pipefail

INITIAL_VERSION="${INITIAL_VERSION:-1.0.0}"
NOTES_FILE="${NOTES_FILE:-${RUNNER_TEMP:-/tmp}/release-notes.md}"

last_tag=$(git describe --tags --abbrev=0 --match 'v[0-9]*.[0-9]*.[0-9]*' 2>/dev/null || true)
range="HEAD"
[ -n "$last_tag" ] && range="$last_tag..HEAD"

breaking=() features=() fixes=() others=()
bump=0 # 0 nada, 1 patch, 2 minor, 3 major
header_re='^([a-z]+)(\([a-z0-9._/-]+\))?(!)?: (.+)$'

while IFS= read -r -d $'\x1e' entry; do
  entry="${entry#$'\n'}"
  [ -z "$entry" ] && continue
  subject="${entry%%$'\x1f'*}"
  body="${entry#*$'\x1f'}"
  [[ "$subject" =~ $header_re ]] || { others+=("$subject"); continue; }
  type="${BASH_REMATCH[1]}"
  bang="${BASH_REMATCH[3]}"
  if [ -n "$bang" ] || grep -qE '^BREAKING[ -]CHANGE: ' <<< "$body"; then
    breaking+=("$subject"); bump=3
  elif [ "$type" = feat ]; then
    features+=("$subject"); (( bump < 2 )) && bump=2
  elif [ "$type" = fix ] || [ "$type" = perf ]; then
    fixes+=("$subject"); (( bump < 1 )) && bump=1
  else
    others+=("$subject")
  fi
done < <(git log "$range" --no-merges --format='%s%x1f%b%x1e')

if [ -z "$last_tag" ]; then
  version="$INITIAL_VERSION"
elif (( bump == 0 )); then
  echo "released=false"
  echo "Nenhum commit feat/fix/breaking desde $last_tag; sem release." >&2
  exit 0
else
  IFS=. read -r major minor patch <<< "${last_tag#v}"
  case $bump in
    3) version="$((major + 1)).0.0" ;;
    2) version="$major.$((minor + 1)).0" ;;
    1) version="$major.$minor.$((patch + 1))" ;;
  esac
fi

section() {
  local title="$1"; shift
  (( $# == 0 )) && return 0
  printf '### %s\n\n' "$title"
  printf -- '- %s\n' "$@"
  printf '\n'
}
{
  section "⚠ Mudanças que quebram" "${breaking[@]}"
  section "Novidades" "${features[@]}"
  section "Correções" "${fixes[@]}"
  section "Outros" "${others[@]}"
} > "$NOTES_FILE"

echo "released=true"
echo "version=$version"
echo "tag=v$version"
echo "notes-file=$NOTES_FILE"
