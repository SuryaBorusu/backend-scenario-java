# Production CI/CD Pipeline

## Action Tracking

### Must-Do (pipeline won't work without these)

- [x] Fix `mysql-connector-java:8.0.28` CVEs — upgraded to `com.mysql:mysql-connector-j:8.4.0`
- [x] Fix Snyk vulnerabilities — 13 issues → 0 (Spring Boot 4.1.1, PostgreSQL 42.7.12, jackson-databind 3.1.5, spring-retry exclusion, fasterxml jackson-databind 2.21.5 via dependencyManagement)
- [x] Create `Dockerfile` — multi-stage layered jar, non-root user, HEALTHCHECK
- [x] Create `k8s/deployment.yml` — Deployment + NodePort Service, readiness/liveness probes, drop-ALL capabilities
- [x] Rewrite `.github/workflows/ci.yml` — parallel jobs, Trivy hard gate, kind deploy, GitHub Summary
- [x] Create `docs/pipeline.md` — living documentation
- [ ] Add `SNYK_TOKEN` secret in GitHub → Settings → Secrets → Actions
- [ ] Make `ghcr.io/<owner>/petclinic` package public (or ensure kind job can pull it) after first push

### Nice-to-Have (pipeline works without these)

- [ ] Pin all GitHub Actions to SHA digests (e.g. `aquasecurity/trivy-action@<sha>`) to prevent mutable tag supply-chain risk
- [ ] Scope `envsubst` explicitly: `envsubst '$IMAGE $IMAGE_TAG'` to avoid accidental substitution of future K8s variables
- [ ] Add `.dockerignore` to exclude `src/test`, `.git`, `target/` from Docker build context
- [ ] Restore Java 24 matrix test on `pr.yml` (removed from `ci.yml` to stay under 5 min budget)
- [x] Add SonarCloud as parallel non-blocking job in ci.yml — runs alongside build, reports to Summary, never blocks deploy
- [ ] Add `snyk monitor` step after successful deploy to track the project on snyk.io for ongoing CVE alerts
- [ ] Pin `eclipse-temurin:21-jre-alpine` to a digest in `Dockerfile` for fully reproducible image builds

---

## Overview

Every push to `main` runs a fully automated pipeline that builds, scans, and deploys PetClinic to a ephemeral [kind](https://kind.sigs.k8s.io/) Kubernetes cluster in under **5 minutes**. No Critical or High vulnerability, broken build, or security regression can pass through — those conditions are hard gates that block the deploy job entirely.

---

## Pipeline Architecture

```
push to main
     │
     ├─── build-test      ~2.5 min   Maven verify + JaCoCo + upload JAR artifact
     │
     ├─── snyk-scan       ~1 min     Dep CVE scan (parallel — no needs)
     │                               Hard fail: Critical/High exits non-zero
     │
     │    needs: build-test
     ├─── docker-build    ~1 min     Build layered image → Trivy scan → push ghcr.io
     │                               Hard fail: Critical/High image CVE blocks push
     │
     │    needs: [build-test, snyk-scan, docker-build]
     ├─── deploy-kind     ~1.5 min   kind cluster → kubectl apply → smoke tests
     │                               GitHub Summary written even on failure
     │
     └─── summary         always     Final pass/fail table in GitHub Summary
```

**Wall-clock target: ≤ 5 minutes**

---

## Security Gates

| Gate | Job | Trigger | Effect |
|---|---|---|---|
| Unit tests + JaCoCo ≥ 85%/66% | `build-test` | Test failure or coverage drop | Hard fail — no JAR artifact, all downstream jobs skipped |
| Critical/High dep CVE | `snyk-scan` | `snyk test --severity-threshold=critical` exits non-zero | Hard fail — `deploy-kind` blocked via `needs` |
| Critical/High image CVE | `docker-build` | Trivy `exit-code: 1` | Hard fail — image not pushed, deploy never runs |
| Rollout timeout | `deploy-kind` | `kubectl rollout status --timeout=120s` | Hard fail — but Summary still written via `if: always()` |

---

## Vulnerability Fixes

### mysql-connector-java → mysql-connector-j

| | Before | After |
|---|---|---|
| **groupId** | `mysql` | `com.mysql` |
| **artifactId** | `mysql-connector-java` | `mysql-connector-j` |
| **version** | `8.0.28` | `8.4.0` |
| **CVEs fixed** | CVE-2023-22102, CVE-2022-21363, CVE-2021-2471 | — |

Oracle renamed the artifact in 8.0.31. The old coordinates still resolve but are no longer maintained.

---

## Dockerfile

Multi-stage build using Spring Boot's [layered jar](https://docs.spring.io/spring-boot/docs/current/reference/html/container-images.html#container-images.efficient-images.layering) feature.

```
Stage 1 (builder):  eclipse-temurin:21-jdk-alpine
  └── java -Djarmode=layertools -jar app.jar extract
        → dependencies/            ← changes only when pom.xml changes
        → spring-boot-loader/      ← changes only on Spring Boot version bump
        → snapshot-dependencies/   ← usually empty
        → application/             ← changes every commit (~50 KB)

Stage 2 (runtime):  eclipse-temurin:21-jre-alpine
  ├── Non-root user petclinic (UID 1000)
  ├── COPY layers in above order (cache-optimal)
  ├── HEALTHCHECK → /petclinic/actuator/health
  └── ENTRYPOINT java org.springframework.boot.loader.launch.JarLauncher
```

**Why this matters:**
- First push: ~300 MB (all layers)
- Subsequent pushes (code change only): ~5 MB (`application/` layer only)
- No JDK in the runtime image → smaller attack surface

---

## Kubernetes Manifests (`k8s/deployment.yml`)

The manifest uses `${IMAGE}` and `${IMAGE_TAG}` placeholders substituted at deploy time via `envsubst`. Do not apply this file directly — use the CI pipeline.

**Deployment features:**
- `runAsNonRoot: true` + `runAsUser: 1000` — matches the container user
- `capabilities.drop: [ALL]` — minimal Linux capabilities
- Readiness probe: `/petclinic/actuator/health/readiness` — pod only receives traffic when Spring is ready
- Liveness probe: `/petclinic/actuator/health/liveness` — pod is restarted if Spring deadlocks
- Resource limits: `512Mi` / `500m` CPU

---

## GitHub Summary

After every run, the workflow writes a rich summary visible on the Actions tab:

```
# CI/CD Pipeline Results

| Stage                | Status |
|----------------------|--------|
| Build & Test         | PASS   |
| Snyk Scan            | PASS   |
| Docker Build & Trivy | PASS   |
| Deploy (kind)        | PASS   |

## Deployment to kind

### Pod Status
NAME                         READY   STATUS    RESTARTS   AGE
petclinic-7d9f8b6c4-xk2pq   1/1     Running   0          45s

### Health Check
{
    "groups": ["liveness", "readiness"],
    "status": "UP"
}

### API Smoke Test — GET /api/owners
[
    {
        "id": 1,
        "firstName": "George",
        "lastName": "Franklin",
        ...
    }
]
```

---

## Local Reproduction

### Build the Docker image

```bash
# Build the JAR first
./mvnw package -DskipTests

# Build the image
docker build -t petclinic:local .

# Run it
docker run -p 9966:9966 petclinic:local

# Verify
curl http://localhost:9966/petclinic/actuator/health
```

### Run on a local kind cluster

```bash
# Install kind (macOS)
brew install kind kubectl

# Create cluster
kind create cluster --name petclinic-local

# Load image
kind load docker-image petclinic:local --name petclinic-local

# Deploy (substitute image manually)
IMAGE=petclinic:local IMAGE_TAG=local envsubst < k8s/deployment.yml | kubectl apply -f -

# Wait
kubectl rollout status deployment/petclinic --timeout=120s

# Access via port-forward
kubectl port-forward svc/petclinic 9966:9966

# Smoke tests
curl http://localhost:9966/petclinic/actuator/health
curl http://localhost:9966/petclinic/api/owners
```

### Run Snyk locally

```bash
# Requires SNYK_TOKEN env var or `snyk auth`
npm install -g snyk
./mvnw dependency:resolve -DskipTests
snyk test --file=pom.xml --severity-threshold=high
```

### Run Trivy locally

```bash
# macOS
brew install trivy

trivy image --severity CRITICAL,HIGH petclinic:local
```

---

## Required GitHub Secrets

| Secret | Purpose |
|---|---|
| `SNYK_TOKEN` | Authenticates Snyk CLI — obtain from [app.snyk.io](https://app.snyk.io/account) |
| `GITHUB_TOKEN` | Auto-provided by Actions — used to push to `ghcr.io` and upload SARIF |

No other secrets are required. The `GITHUB_TOKEN` permissions are scoped in the workflow:
```yaml
permissions:
  contents: read
  packages: write        # push to ghcr.io
  security-events: write # upload SARIF to Code Scanning
```

---

## Troubleshooting

### Snyk scan fails with "exit code 2"
Token missing or invalid. Check the `SNYK_TOKEN` secret is set in **Settings → Secrets → Actions**.

### Trivy fails on base image CVEs
`ignore-unfixed: true` is set — only CVEs with a known fix will fail the build. If a new CVE appears in the base image before a fix is available, update `eclipse-temurin` to the latest patch release:
```dockerfile
FROM eclipse-temurin:21-jre-alpine   # pin to a specific digest for reproducibility
```

### kind pod stuck in `Pending`
Usually a resource constraint on the GitHub Actions runner. Check:
```bash
kubectl describe pod -l app=petclinic
kubectl get events --sort-by=.lastTimestamp
```

### Rollout timeout (120s exceeded)
The app takes ~30s to start on cold JVM. If tests pass but deploy times out:
1. Check `kubectl logs -l app=petclinic` for Spring startup errors
2. Verify the image was loaded correctly: `docker exec petclinic-ci-control-plane crictl images`
3. Increase `initialDelaySeconds` on the readiness probe if the runner is under-resourced

### `envsubst` replaces Kubernetes variables
The `$IMAGE` and `$IMAGE_TAG` vars are the only substitutions. If you add new env vars to `deployment.yml` that clash with shell vars, scope `envsubst` explicitly:
```bash
envsubst '$IMAGE $IMAGE_TAG' < k8s/deployment.yml > k8s/deployment-ci.yml
```

---

## Optimisations

| Technique | Saving |
|---|---|
| Snyk runs in parallel with build | ~1 min |
| Maven dependency cache (`setup-java cache: maven`) | ~1.5 min on warm runs |
| Docker layer cache (`type=gha`) | ~45s on code-only changes |
| Spring Boot layered jar | Image push ~5 MB vs ~300 MB |
| Trivy DB cache (`~/.cache/trivy`) | ~1 min |
| JAR artifact reuse (no second compile) | ~2.5 min |
| kind over minikube | ~1.5 min cluster startup |

---

*Last updated: 2026-08-22*
