# platform-pipelines-templates

Esteira reutilizável do golden path. Os serviços **não copiam** a esteira: eles chamam este
repositório por versão.

```yaml
jobs:
  ci:
    uses: gerffeson-lab/platform-pipelines-templates/.github/workflows/ci-java.yaml@v1
    secrets: inherit
```

## Estrutura

| Camada | Onde fica | Papel | Quem usa |
|---|---|---|---|
| Pipelines | `.github/workflows/ci-*.yaml` (e `cd-*` na fase 2) | Esteira completa de uma stack, já com os gates | Os serviços (interface pública) |
| Steps | `actions/<domínio>/<nome>/action.yml` | Um passo isolado e versionado (lint, scan, build, push) | Os pipelines; pode ser usado avulso |
| Release | `.github/workflows/release-semver.yaml`, `lint-pr-title.yaml` | Versão semântica automática por Conventional Commits | Qualquer repo versionado |
| Auto-teste | `.github/workflows/test.yaml` + `tests/` | Testa as actions a cada PR e antes de cada release | Este repo (`pr.yaml`, `release.yaml`) |

Os reusable workflows do GitHub precisam ficar todos em `.github/workflows/`, sem subpastas.
Por isso a organização por domínio fica em `actions/`.

```
actions/
  openapi/lint                 # Redocly, ruleset padrão da plataforma
  openapi/breaking-changes     # oasdiff contra a branch de destino
  security/secret-scan         # Gitleaks
  security/sbom                # Syft, CycloneDX
  security/sca                 # Grype sobre o SBOM ou a imagem
  sonar/maven                  # SAST + quality gate (SonarQube/SonarCloud)
  java/maven-build             # mvn verify + JAR como artifact
  container/build-push         # build, scan da imagem, tags por branch/semver/sha e push
  release/next-version         # versão semântica por Conventional Commits
```

## ci-java.yaml

| Job | Quando | O que faz | Bloqueia? |
|---|---|---|---|
| contrato OpenAPI | sempre | Lint com Redocly (`redocly.yaml` do serviço ou o padrão da plataforma) | sim |
| | PR | Breaking change contra a branch de destino (oasdiff) | sim |
| secret scanning | sempre | Gitleaks no histórico | sim |
| build, testes e SAST | sempre | `mvn verify` com cobertura (JaCoCo, ligado pela esteira) | sim |
| | sempre | **SAST** no Sonar, esperando o quality gate | sim |
| | sempre | **SBOM** CycloneDX do JAR final (artifact `sbom`, 90 dias) | — |
| SCA | sempre | **Grype** sobre o SBOM: severidade alta ou maior com correção disponível | sim |
| imagem | push em develop, release/*, main e tags | Build, **scan da imagem** (Grype) e push para o registry | scan só relata (veja abaixo) |

Entradas: `java-version` (padrão `21`), `openapi-path` (padrão `api/openapi.yaml`),
`publish-image` (padrão `true`), `sonar-project-key` (padrão `<dono>_<repositório>`).

### Configuração (na org, não no serviço)

| Tipo | Nome | Valor |
|---|---|---|
| Secret | `SONAR_TOKEN` | Token do SonarQube/SonarCloud. **Obrigatório**: sem ele o build falha |
| Variável | `SONAR_HOST_URL` | Padrão `https://sonarcloud.io` |
| Variável | `SONAR_ORGANIZATION` | Só no SonarCloud |

O serviço chama a esteira com `secrets: inherit`. As regras do quality gate (ex.: cobertura
em código novo) ficam no Sonar, não no repositório do serviço.

### Por que o scan da imagem ainda não bloqueia

As vulnerabilidades da imagem vêm dos pacotes do sistema operacional da imagem base (UBI),
que o time do serviço não consegue corrigir. Hoje a própria `ubi9/openjdk-21-runtime` mais
recente tem vulnerabilidades altas com correção disponível. Bloquear agora travaria todos os
serviços. O caminho é a plataforma manter uma **imagem base curada** (reconstruída com os
patches, com scan próprio); quando ela existir, o padrão do `fail-on` da imagem passa para
`high`. O SCA da aplicação, que o time corrige, já bloqueia.

### SBOM

Hoje fica como artifact do run (90 dias). Para valer além do CI:

1. Anexar à imagem no registry como attestation (cosign/OCI), para o SBOM viajar com a imagem
   que vai para produção.
2. Enviar para uma ferramenta de gestão de vulnerabilidades (Dependency-Track, Tenable...),
   que reavalia os SBOMs quando sai uma CVE nova, sem precisar rodar o CI de novo.

## Versionamento (automático)

Este repositório usa o próprio template de release (`release-semver.yaml`):

1. O PR precisa de um título em Conventional Commits (`lint-pr-title.yaml`), e o merge é por
   squash, então o título vira o commit na `main`.
2. A cada merge na `main`, o workflow `release` roda os testes e calcula a versão a partir dos
   commits desde a última tag:

   | Commit | Exemplo | Versão |
   |---|---|---|
   | `feat!:` ou `BREAKING CHANGE:` no corpo | `feat!: remove input publish-image` | major (`v2.0.0`) |
   | `feat:` | `feat(openapi): adiciona regra X` | minor (`v1.1.0`) |
   | `fix:` / `perf:` | `fix: corrige cache do maven` | patch (`v1.0.1`) |
   | `docs:`, `chore:`, `ci:`, `refactor:`... | `docs: ajusta README` | sem release |

3. Cria a tag, a GitHub Release com as notas agrupadas e move a tag de major (`v1`).

Nada é commitado de volta na `main` (diferente do release-it com CHANGELOG.md): o histórico
fica nas Releases e a `main` pode ser protegida por ruleset sem exceções.

Numa `v2`, os pipelines passam a referenciar as actions com `@v2`. Não há arquivos com
sufixo `-v2`: a versão é a tag do repositório inteiro.

Outros repos (helm-library, libs internas, serviços) usam o mesmo template:

```yaml
jobs:
  release:
    uses: gerffeson-lab/platform-pipelines-templates/.github/workflows/release-semver.yaml@v1
    permissions:
      contents: write
```

## Diferenças da POC para a plataforma do banco

| POC | Banco |
|---|---|
| ghcr.io | Quay (com scan de imagem) |
| Runners hospedados pelo GitHub | Runners self-hosted (ARC no OpenShift), com acesso à rede interna |
| Actions públicas referenciadas direto | Allowlist do Enterprise ou espelho interno das actions de terceiros |
| Dependências direto do Maven Central | Nexus (proxy do Central e libs internas) |
| Grype (SCA e imagem), Syft (SBOM) | Os mesmos, ou a ferramenta definida por Segurança (ex.: Tenable) |
| SonarCloud | SonarQube quality gate |
| Imagem base UBI pública | Imagem base curada pela plataforma, com scan bloqueante |
| `ci.yaml` copiado do template | Required workflow via ruleset da org: o CI roda mesmo se o time removê-lo |
