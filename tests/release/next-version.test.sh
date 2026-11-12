#!/usr/bin/env bash
# Testa actions/release/next-version/next-version.sh num repositório Git temporário.
set -euo pipefail

script="$(cd "$(dirname "$0")/../.." && pwd)/actions/release/next-version/next-version.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$work"
git init -q -b main
git config user.email test@example.com
git config user.name test

failures=0
commit() { git commit -q --allow-empty -m "$1" ${2:+-m "$2"}; }
expect() {
  local desc="$1" want="$2" got
  got=$(NOTES_FILE="$work/notes.md" bash "$script" 2>/dev/null | grep -E '^(version|released)=' | tail -1)
  if [ "$got" = "$want" ]; then echo "ok   - $desc"; else echo "FAIL - $desc: esperado '$want', obtido '$got'"; failures=$((failures + 1)); fi
}

commit "chore: inicio";                          expect "primeira release usa a versão inicial" "version=1.0.0"
git tag v1.0.0
commit "docs: ajusta readme";                    expect "docs não gera release" "released=false"
commit "fix(openapi): corrige base-ref";         expect "fix gera patch" "version=1.0.1"
commit "feat(java): novo input";                 expect "feat gera minor" "version=1.1.0"
git tag v1.1.0
commit "refactor: renomeia input" "BREAKING CHANGE: spec virou contract"
                                                 expect "BREAKING CHANGE no corpo gera major" "version=2.0.0"
git tag v2.0.0
commit "feat!: remove ci-node";                  expect "! gera major" "version=3.0.0"
git tag v3.0.0
commit "atualiza coisas";                        expect "commit fora do padrão não gera release" "released=false"

exit "$failures"
