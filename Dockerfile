# ── Stage 1: Extract Spring Boot layered jar ─────────────────────────────────
# Uses JDK to run jarmode — produces layer directories for optimal cache reuse.
FROM eclipse-temurin:21-jdk-alpine AS builder
WORKDIR /workspace
COPY target/*.jar app.jar
RUN java -Djarmode=layertools -jar app.jar extract

# ── Stage 2: Runtime image ────────────────────────────────────────────────────
# JRE-only image (~100MB smaller than JDK). Layers copied in least-to-most
# frequently changed order so Docker cache is invalidated only for changed layers.
FROM eclipse-temurin:21-jre-alpine AS runtime

# Non-root user — principle of least privilege
RUN addgroup -S petclinic && adduser -S petclinic -G petclinic

WORKDIR /app

# Layer 1: third-party dependencies (changes only when pom.xml changes)
COPY --from=builder /workspace/dependencies/ ./
# Layer 2: Spring Boot loader (changes only on Spring Boot version bump)
COPY --from=builder /workspace/spring-boot-loader/ ./
# Layer 3: snapshot dependencies (usually empty in releases)
COPY --from=builder /workspace/snapshot-dependencies/ ./
# Layer 4: application classes (changes on every code change — ~50 KB)
COPY --from=builder /workspace/application/ ./

USER petclinic

EXPOSE 9966

# Healthcheck via actuator — container is healthy only when Spring is fully up
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 
    CMD wget -qO- http://localhost:9966/petclinic/actuator/health | grep -q '"status":"UP"' || exit 1

ENTRYPOINT ["java", "org.springframework.boot.loader.launch.JarLauncher"]
