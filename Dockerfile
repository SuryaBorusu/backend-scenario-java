# Spring Boot 4 executable JAR — single-stage, non-root runtime image.
# The JAR is built by Maven in CI (./mvnw package) and passed in via artifact.
# Note: -Djarmode=layertools was removed in Spring Boot 4; using direct JAR copy.
FROM eclipse-temurin:21-jre-alpine

RUN addgroup -S petclinic && adduser -S petclinic -G petclinic

WORKDIR /app

COPY --chown=petclinic:petclinic target/*.jar app.jar

USER petclinic

EXPOSE 9966

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 CMD wget -qO- http://localhost:9966/petclinic/actuator/health | grep -q '"status":"UP"' || exit 1

ENTRYPOINT ["java", "-jar", "app.jar"]
