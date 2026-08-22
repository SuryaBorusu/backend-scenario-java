
# Observability — Prometheus & Grafana

This document describes the full observability setup for the Spring PetClinic REST API:
Prometheus metrics exposure, local observability stack, and a four-panel Grafana dashboard.

---

## Architecture

```
Spring Boot API (port 9966)
        │
        │  /actuator/prometheus  (Micrometer → Prometheus format)
        ▼
Prometheus (port 9090)
        │  scrapes every 15s
        ▼
Grafana (port 3000)
        │  reads Prometheus as data source
        ▼
Four-panel dashboard (Request Rate, Error Rate, P95 Latency, Memory + CPU)
```

---

## Prerequisites — Rancher Desktop (macOS)

This project uses **Rancher Desktop** instead of Docker Desktop. There are two key differences
that affect the observability stack:

| Item | Docker Desktop | Rancher Desktop |
|---|---|---|
| Docker socket | `/var/run/docker.sock` | `~/.rd/docker.sock` |
| `host.docker.internal` | ✅ Resolves automatically | ❌ Not injected into containers |
| Host IP from container | `host.docker.internal` | `172.17.0.1` (bridge gateway) |

### Switch to the Rancher Desktop Docker context

```bash
docker context use rancher-desktop
```

Verify it works:

```bash
docker info | grep "Server Version"
```

> If you see `localhost-context` as active (tcp://localhost:2375), commands will fail.
> Always ensure `rancher-desktop` is the active context before running `docker compose`.

---

## Step 1 — Add Micrometer Prometheus to the Java API

### 1.1 Dependency (`pom.xml`)

Add inside `<dependencies>`:

```xml
<!-- Micrometer Prometheus registry — exposes /actuator/prometheus -->
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-registry-prometheus</artifactId>
</dependency>
```

> Version is managed by `spring-boot-starter-parent` — do not specify a version manually.

### 1.2 Actuator configuration (`src/main/resources/application.properties`)

```properties
# Expose prometheus and health endpoints over HTTP
management.endpoints.web.exposure.include=health,info,prometheus
management.endpoint.prometheus.access=unrestricted
management.metrics.export.prometheus.enabled=true

# Tag every metric with the application name
management.metrics.tags.application=petclinic
```

### 1.3 What gets instrumented automatically

Spring Boot auto-configures Micrometer with the following metrics out of the box —
no additional Java code is required:

| Metric family | Prometheus name | Description |
|---|---|---|
| HTTP request rate | `http_server_requests_seconds_count` | Total requests per endpoint |
| HTTP request duration | `http_server_requests_seconds_bucket` | Histogram buckets for latency |
| HTTP error rate | `http_server_requests_seconds_count{status=~"5.."}` | 5xx responses |
| JVM heap memory | `jvm_memory_used_bytes{area="heap"}` | Live heap usage |
| CPU usage | `process_cpu_usage` | Process CPU (0–1 ratio) |

---

## Step 2 — Verify the Prometheus endpoint locally

```bash
# Start the API (H2, default profile)
./mvnw spring-boot:run

# In a second terminal — confirm metrics are exposed
curl -s http://localhost:9966/petclinic/actuator/prometheus | head -40
```

Expected output begins with:

```
# HELP http_server_requests_seconds_bucket  ...
# TYPE http_server_requests_seconds histogram
http_server_requests_seconds_bucket{...
```

---

## Step 3 — Local observability stack (Docker Compose)

### 3.1 File layout

```
observability/
├── prometheus.yml          ← Prometheus scrape config
└── grafana/
    └── provisioning/
        ├── datasources/
        │   └── prometheus.yml   ← Auto-wires Prometheus as Grafana data source
        └── dashboards/
            ├── dashboard.yml    ← Tells Grafana where to load dashboard JSON from
            └── petclinic.json   ← The four-panel dashboard
```

### 3.2 `observability/prometheus.yml`

```yaml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: petclinic
    metrics_path: /petclinic/actuator/prometheus
    static_configs:
      - targets:
          - 172.17.0.1:9966  # Rancher Desktop bridge gateway — reaches the host from inside a container
```

> **Why `172.17.0.1`?** Prometheus runs inside Docker. `localhost` inside a container refers to
> the container itself, not your Mac. With **Rancher Desktop**, `host.docker.internal` is not
> injected — use `172.17.0.1` (the Docker bridge gateway) to reach the host instead.
> Verify with: `docker network inspect bridge | grep Gateway`

### 3.3 `docker-compose.yml` additions (under `observability` profile)

```yaml
  prometheus:
    image: prom/prometheus:v2.52.0
    ports:
      - "9090:9090"
    volumes:
      - ./observability/prometheus.yml:/etc/prometheus/prometheus.yml:ro
    profiles:
      - observability

  grafana:
    image: grafana/grafana:10.4.2
    ports:
      - "3000:3000"
    environment:
      - GF_AUTH_ANONYMOUS_ENABLED=true
      - GF_AUTH_ANONYMOUS_ORG_ROLE=Admin
      - GF_AUTH_DISABLE_LOGIN_FORM=true
    volumes:
      - ./observability/grafana/provisioning:/etc/grafana/provisioning:ro
    depends_on:
      - prometheus
    profiles:
      - observability
```

### 3.4 `observability/grafana/provisioning/datasources/prometheus.yml`

```yaml
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
```

### 3.5 `observability/grafana/provisioning/dashboards/dashboard.yml`

```yaml
apiVersion: 1

providers:
  - name: PetClinic
    type: file
    options:
      path: /etc/grafana/provisioning/dashboards
```

---

## Step 4 — Grafana Dashboard

### Panel definitions

All panels are `timeseries` type. Every panel sets `fieldConfig.defaults.unit` explicitly.

#### Panel 1 — Request Rate

| Property | Value |
|---|---|
| Title | `Request Rate` |
| PromQL | `sum(rate(http_server_requests_seconds_count{application="petclinic"}[5m]))` |
| Unit | `reqps` (requests per second) |
| `fieldConfig.defaults.unit` | `reqps` |

#### Panel 2 — Error Rate

| Property | Value |
|---|---|
| Title | `Error Rate` |
| PromQL | `sum(rate(http_server_requests_seconds_count{application="petclinic",status=~"5.."}[5m])) / sum(rate(http_server_requests_seconds_count{application="petclinic"}[5m]))` |
| Unit | `percentunit` (0–1 ratio rendered as %, e.g. `0.05` → `5%`) |
| `fieldConfig.defaults.unit` | `percentunit` |

> **Important:** `percentunit` expects values in the 0–1 range. Do **not** multiply by 100.
> Grafana handles the `%` rendering automatically.

#### Panel 3 — P95 Latency

| Property | Value |
|---|---|
| Title | `P95 Latency` |
| PromQL | `histogram_quantile(0.95, sum(rate(http_server_requests_seconds_bucket{application="petclinic"}[5m])) by (le))` |
| Unit | `s` (seconds) |
| `fieldConfig.defaults.unit` | `s` |

#### Panel 4 — Memory + CPU (Saturation)

Two series in one panel:

| Series | PromQL | Unit |
|---|---|---|
| Heap Memory | `sum(jvm_memory_used_bytes{application="petclinic",area="heap"})` | `bytes` |
| CPU Usage | `process_cpu_usage{application="petclinic"}` | `percentunit` |

> Two series with different units in one panel: set `fieldConfig.defaults.unit` to `percentunit`
> and override the memory series with `fieldConfig.overrides` targeting `bytes`.

---

## Step 5 — Start the stack and generate traffic

```bash
# Terminal 1 — start the API
./mvnw spring-boot:run

# Terminal 2 — start Prometheus + Grafana
docker compose --profile observability up

# Terminal 3 — generate traffic (50 requests, 0.2s apart)
for i in {1..50}; do curl -s -o /dev/null http://localhost:9966/petclinic/api/owners; sleep 0.2; done
```

### Verify Prometheus is scraping

Open `http://localhost:9090/targets` — the `petclinic` target should show **UP**.

### Open Grafana

`http://localhost:3000` — anonymous admin access, no login required.
The **PetClinic** dashboard is pre-provisioned and ready.

---

## Step 6 — Expected dashboard behaviour

| Panel | What you should see |
|---|---|
| Request Rate | Rising rate during traffic generation, settling after |
| Error Rate | `0%` for clean requests; spikes if 5xx responses occur |
| P95 Latency | Latency in seconds (e.g. `12ms` shown as `0.012 s`) |
| Memory + CPU | Heap climbing during load; CPU % spiking then settling |

### Percentage rendering checklist

- Error Rate reads `5%` not `0.05` → `fieldConfig.defaults.unit: percentunit` ✅
- CPU reads `3%` not `0.03` → `fieldConfig.defaults.unit: percentunit` ✅
- Both rely on Grafana's `percentunit` formatting — values must stay in 0–1 range in PromQL

---

## Improvements Over Naive Setup

| Naive approach | Improved approach used here |
|---|---|
| Manually import dashboard JSON via Grafana UI | Grafana provisioning — dashboard auto-loaded on startup |
| Prometheus scrapes `localhost` | Uses `172.17.0.1` (bridge gateway) — required for Rancher Desktop; `host.docker.internal` not available |
| Grafana requires login | `GF_AUTH_ANONYMOUS_ENABLED=true` + `GF_AUTH_ANONYMOUS_ORG_ROLE=Admin` |
| Hardcoded micrometer version | Inherited from `spring-boot-starter-parent` — always aligned |
| No application tag on metrics | `management.metrics.tags.application=petclinic` — filters metrics by app in multi-service setups |
| Prometheus + Grafana always running | `--profile observability` — opt-in, doesn't pollute default `docker compose up` |

---

## File Checklist

| File | Action |
|---|---|
| `pom.xml` | Add `micrometer-registry-prometheus` dependency |
| `src/main/resources/application.properties` | Add actuator + metrics config |
| `docker-compose.yml` | Add `prometheus` and `grafana` services under `observability` profile |
| `observability/prometheus.yml` | Create — Prometheus scrape config |
| `observability/grafana/provisioning/datasources/prometheus.yml` | Create — Grafana data source |
| `observability/grafana/provisioning/dashboards/dashboard.yml` | Create — Grafana dashboard provider |
| `observability/grafana/provisioning/dashboards/petclinic.json` | Create — four-panel dashboard JSON |

---

## Quick Reference — Spin Up, Test & Tear Down

### Prerequisites

```bash
# Ensure Rancher Desktop is running, then switch to its Docker context
docker context use rancher-desktop
docker info | grep "Server Version"   # should print a version, not an error
```

### Step 1 — Find your host IP (needed if prometheus.yml target needs updating)

```bash
ifconfig | grep "inet " | grep -v 127.0.0.1
# Use the first IP (e.g. 192.168.x.x) in observability/prometheus.yml
```

### Step 2 — Start the Spring Boot API

```bash
# Terminal 1
./mvnw spring-boot:run
```

Wait for: `Started PetClinicApplication`

Verify:

```bash
curl -s http://localhost:9966/petclinic/actuator/health
# Expected: {"status":"UP"}

curl -s http://localhost:9966/petclinic/actuator/prometheus | grep "http_server_requests_seconds_bucket" | head -3
# Expected: bucket lines with le= labels
```

### Step 3 — Start Prometheus + Grafana

```bash
# Terminal 2
docker compose --profile observability up -d
```

Verify Prometheus is scraping:

```bash
# Check target status — should show UP within 15s
open http://localhost:9090/targets
```

If target shows DOWN, check the host IP in `observability/prometheus.yml` matches your current IP:

```bash
docker ps --filter name=prometheus --format "{{.ID}}" | \
  xargs -I{} docker exec {} sh -c "ip route | grep default"
# Note the gateway IP, update prometheus.yml if needed, then:
docker compose --profile observability restart prometheus
```

### Step 4 — Run the load test

```bash
# Terminal 3
./load-test.sh
```

This runs 4 phases:
1. Warm-up — 50 requests across all endpoints
2. Sustained load — 200 GET `/owners`
3. Error traffic — 30 × 404s (populates 4xx error rate panel)
4. Burst — 100 parallel requests (spikes CPU + latency)

### Step 5 — View Grafana dashboard

Open `http://localhost:3000` — no login required.

Navigate to **Dashboards → PetClinic** (auto-provisioned).

| Panel | Expected |
|---|---|
| Request Rate | Rising req/s during load, settling after |
| Error Rate | 4xx line visible; 5xx empty = healthy app |
| P95 Latency | Latency in seconds (e.g. `0.012 s` = 12ms) |
| Memory + CPU | Heap bytes + CPU % spiking during burst |

> **Note:** P95 Latency requires at least one full 5-minute `rate()` window.
> If empty, wait 5 minutes and re-run `./load-test.sh`.

### Verify metrics directly in Prometheus

```bash
# Request rate
curl -s -G "http://localhost:9090/api/v1/query" \
  --data-urlencode 'query=sum(rate(http_server_requests_seconds_count{application="petclinic"}[5m]))' \
  | python3 -m json.tool

# Error rate (4xx + 5xx)
curl -s -G "http://localhost:9090/api/v1/query" \
  --data-urlencode 'query=sum(rate(http_server_requests_seconds_count{application="petclinic",status=~"4..|5.."}[5m])) / sum(rate(http_server_requests_seconds_count{application="petclinic"}[5m]))' \
  | python3 -m json.tool

# P95 latency
curl -s -G "http://localhost:9090/api/v1/query" \
  --data-urlencode 'query=histogram_quantile(0.95, sum(rate(http_server_requests_seconds_bucket{application="petclinic"}[5m])) by (le))' \
  | python3 -m json.tool

# Heap memory
curl -s -G "http://localhost:9090/api/v1/query" \
  --data-urlencode 'query=sum(jvm_memory_used_bytes{application="petclinic",area="heap"})' \
  | python3 -m json.tool
```

### Clean Up

```bash
# Stop Prometheus + Grafana
docker compose --profile observability down

# Stop the Spring Boot API (find and kill the process on port 9966)
lsof -ti :9966 | xargs kill

# Optional — remove Docker images to free disk space
docker rmi prom/prometheus:v2.52.0 grafana/grafana:10.4.2
```
