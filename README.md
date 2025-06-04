# Zadanie 2: Pipeline GitHub Actions dla budowania i publikowania obrazów Docker

## Opis rozwiązania

W ramach tego zadania opracowano łańcuch (pipeline) w usłudze GitHub Actions, który buduje obraz kontenera na podstawie Dockerfile-a oraz kodów źródłowych aplikacji, a następnie przesyła go do publicznego repozytorium autora na GitHub Container Registry (ghcr.io). Proces ten spełnia wszystkie wymagane warunki określone w treści zadania.

## Etapy implementacji

### 1. Struktura projektu

Repozytorium zawiera:
- Plik `.github/workflows/docker-build.yml` - definicja workflow GitHub Actions
- `Dockerfile` - instrukcje budowania obrazu kontenera
- `main.go`, `go.mod`, `go.sum` - przykładowa aplikacja Go

### 2. Workflow GitHub Actions

Główne etapy pipeline'u:
1. **Checkout kodu źródłowego** - pobranie najnowszej wersji kodu z repozytorium
2. **Konfiguracja QEMU i Buildx** - przygotowanie środowiska do budowania obrazów wieloplatformowych
3. **Logowanie do rejestrów** - uwierzytelnienie w DockerHub (dla cache) i GitHub Container Registry (dla obrazów)
4. **Ekstrakcja metadanych** - określenie tagów i etykiet dla obrazu
5. **Budowanie obrazu** - bez publikacji, na potrzeby skanu bezpieczeństwa
6. **Skan bezpieczeństwa** - analiza obrazu pod kątem podatności za pomocą Trivy
7. **Publikacja obrazu** - tylko gdy nie wykryto krytycznych lub wysokich zagrożeń

### 3. Obsługa wymagań szczegółowych

#### a. Wsparcie dla wielu architektur

W pliku workflow zdefiniowano platformy docelowe za pomocą parametru `platforms`:
```yaml
platforms: linux/amd64,linux/arm64
```

Dodatkowo, skonfigurowano akcję `docker/setup-qemu-action`, która umożliwia emulację różnych architektur sprzętowych podczas budowania.

#### b. Wykorzystanie cache

W rozwiązaniu zastosowano Docker BuildKit Cache eksportowany do rejestru DockerHub:

```yaml
cache-from: type=registry,ref=${{ secrets.DOCKERHUB_USERNAME }}/cache:${{ github.ref_name }}
cache-to: type=registry,ref=${{ secrets.DOCKERHUB_USERNAME }}/cache:${{ github.ref_name }},mode=max
```

Tryb `max` zapewnia przechowywanie wszystkich warstw pośrednich, co maksymalizuje wydajność i szybkość kolejnych operacji budowania.

#### c. Test CVE obrazu

Do skanowania obrazu pod kątem zagrożeń wybrano narzędzie Trivy, które jest lekkie i integruje się dobrze z GitHub Actions.

W implementacji zastosowano dwuetapowe podejście do budowania i skanowania obrazu:

1. Najpierw obraz jest budowany i zapisywany lokalnie (bez publikacji):
```yaml
- name: Build and push Docker image
  id: build
  uses: docker/build-push-action@v4
  with:
    context: .
    platforms: linux/amd64,linux/arm64
    push: false
    tags: ${{ steps.meta.outputs.tags }}
    labels: ${{ steps.meta.outputs.labels }}
    outputs: type=docker,dest=image.tar
    
- name: Load image
  run: |
    docker load < image.tar
    docker image ls
```

2. Następnie lokalny obraz jest skanowany przy użyciu Trivy:
```yaml
- name: Run Trivy vulnerability scanner
  uses: aquasecurity/trivy-action@master
  with:
    image-ref: $(echo "${{ steps.meta.outputs.tags }}" | tr ' ' '\n' | head -1)
    format: 'sarif'
    output: 'trivy-results.sarif'
    exit-code: 1
    ignore-unfixed: true
    vuln-type: 'os,library'
    severity: 'CRITICAL,HIGH'
```

Dzięki ustawieniu `exit-code: 1` dla poziomów `CRITICAL,HIGH`, workflow zakończy się błędem, jeśli zostaną znalezione podatności o wysokim poziomie ryzyka. Obraz zostanie przesłany do GitHub Container Registry tylko wtedy, gdy skan przebiegnie pomyślnie.

**Uwaga:** W przypadku obrazów wieloplatformowych konieczne jest zastosowanie rozwiązania z zapisem obrazu do pliku tar i wczytaniem go do lokalnego demona Dockera przed skanowaniem. Zapewnia to poprawne działanie Trivy, które w przeciwnym przypadku może mieć problem z prawidłowym rozpoznaniem obrazu.

## Strategia tagowania

W implementacji przyjęto zaawansowaną strategię tagowania obrazów z wykorzystaniem `docker/metadata-action`. Rozwiązanie to automatycznie generuje zestaw tagów na podstawie kontekstu uruchomienia workflow:

1. **Tagi bazujące na gałęziach** - obraz budowany z określonej gałęzi otrzymuje tag z jej nazwą
2. **Tagi bazujące na Pull Requestach** - obrazy z PR otrzymują specjalne tagi do testowania
3. **Tagi semantyczne** - jeśli commit ma tag wersji (np. v1.2.3), generowane są tagi: `1.2.3`, `1.2`, `1`
4. **Tagi bazujące na commicie** - skrócony i pełny hash commita
5. **Tag latest** - przypisywany obrazowi z domyślnej gałęzi (zazwyczaj `main`)

Dla danych cache wykorzystywana jest konwencja:
```
username/cache:nazwa_gałęzi
```

### Uzasadnienie wyboru strategii tagowania

Wybrana strategia ma kilka istotnych zalet:

1. **Pełna identyfikowalność** - każdy obraz można powiązać z konkretnym stanem kodu źródłowego
2. **Wsparcie dla wersjonowania semantycznego** - zgodność z konwencją [SemVer](https://semver.org/)
3. **Optymalne wykorzystanie cache** - osobne cache dla każdej gałęzi zapobiega konfliktom i zapewnia szybsze buildy
4. **Łatwość wdrażania** - tag `latest` zawsze wskazuje na najnowszą wersję z głównej gałęzi

Jest to zgodne z rekomendacjami [Docker](https://docs.docker.com/develop/dev-best-practices/) dotyczącymi tagowania obrazów oraz z praktykami CI/CD opisanymi w dokumentacji [GitHub Actions](https://docs.github.com/en/actions/publishing-packages/publishing-docker-images).

## Konfiguracja i uruchomienie

Aby skonfigurować i uruchomić pipeline, należy:

1. Dodać następujące sekrety w ustawieniach repozytorium GitHub:
   - `DOCKERHUB_USERNAME` - nazwa użytkownika na DockerHub
   - `DOCKERHUB_TOKEN` - token dostępu do DockerHub

2. Upewnić się, że workflow ma odpowiednie uprawnienia do zapisu pakietów (packages) w repozytorium GitHub.

3. Wykonać push zmian do gałęzi głównej, co automatycznie uruchomi pipeline.

4. Workflow zostanie uruchomiony, a jego wyniki będą widoczne w zakładce "Actions" w repozytorium.

## Podsumowanie

Opracowany łańcuch GitHub Actions spełnia wszystkie wymagania zadania, zapewniając:
- Wsparcie dla wielu architektur
- Efektywne wykorzystanie danych cache
- Bezpieczeństwo publikowanych obrazów poprzez skanowanie podatności
- Elastyczną i dobrze przemyślaną strategię tagowania

Dodatkowo, rezultaty skanów bezpieczeństwa są zapisywane w formacie SARIF i publikowane w zakładce "Security" repozytorium, co zwiększa transparentność procesu i ułatwia monitorowanie bezpieczeństwa obrazów.
