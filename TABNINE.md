# TABNINE.md — backend-scenario-java

## Project Overview

REST-only backend for the Spring PetClinic sample application, adapted as the hands-on project for Thoughtworks' **AIFSD 101 DevSecOps training**. Participants build CI/CD pipelines, observability tooling, and security hardening from scratch on top of this codebase.

- **Runtime:** Java 21+ (Spring Boot 4.1, Spring Framework 7)
- **Build tool:** Maven 3.9+ (wrapper `./mvnw` committed — always use it)
- **Default database:** H2 in-memory (no external dependency needed for local dev or tests)
- **No UI** — pure REST API consumed by the separate [spring-petclinic-angular](https://github.com/spring-petclinic/spring-petclinic-angular) frontend

---

## Architecture

```
openapi.yml  ──(OpenAPI Generator)──▶  rest/dto/**Dto.java        (generated DTOs)
                                   ──▶  rest/api/**Api.java        (generated controller interfaces)
                                         │
                                         ▼
                          rest/controller/v1/**RestControllerV1.java  (hand-written impls)
                                         │  uses MapStruct mappers
                                         ▼
                              service/ClinicService  (facade interface)
                                         │
                                         ▼
                         repository/{jdbc,jpa,springdatajpa}/**  (swappable via profile)
```

### Key packages

| Package | Purpose |
|---|---|
| `model` | JPA entities (`Owner`, `Pet`, `Vet`, `Visit`, `PetType`, `Specialty`, `User`) |
| `repository` | Three interchangeable implementations: `jdbc`, `jpa`, `springdatajpa` |
| `service` | `ClinicService` / `UserService` — single entry point for all controllers |
| `rest/controller/v1` | V1 REST controllers implementing generated `*Api` interfaces |
| `rest/controller/v2` | V2 controllers for `Owner` and `Pet` (pagination support) |
| `rest/dto` | **Generated** — do not edit by hand; regenerated from `openapi.yml` on every build |
| `rest/api` | **Generated** — controller interfaces from `openapi.yml` |
| `mapper` | MapStruct mappers between domain models and DTOs (also generated at compile time) |
| `security` | `BasicAuthenticationConfig` / `DisableSecurityConfig` toggled by `petclinic.security.enable` |
| `config` | `SwaggerConfig` for Springdoc/OpenAPI UI |

### Generated code

Both `rest/dto` and `rest/api` are produced during `generate-sources` by the OpenAPI Generator Maven plugin. MapStruct mapper implementations are produced by the `mapstruct-processor` annotation processor. Neither set should be edited manually — always regenerate via build.

---

## Building & Running

```bash
# Run locally (H2, spring-data-jpa by default)
./mvnw spring-boot:run

# Full build: compile + generate sources + test + coverage check
./mvnw verify

# Skip tests (fast build / source generation only)
./mvnw package -DskipTests
```

### Useful URLs (local)

| URL | Description |
|---|---|
| `http://localhost:9966/petclinic/` | API root |
| `http://localhost:9966/petclinic/swagger-ui.html` | Swagger UI |
| `http://localhost:9966/petclinic/v3/api-docs` | OAS 3.1 JSON spec |
| `http://localhost:9966/petclinic/actuator/health` | Health check |
| `http://localhost:9966/petclinic/h2-console` | H2 console (JDBC URL: `jdbc:h2:mem:petclinic`, user: `sa`, no password) |

---

## Database Profiles

Switch by editing `spring.profiles.active` in `src/main/resources/application.properties`.

| Database | Profile value | External dependency |
|---|---|---|
| H2 (default) | `h2,spring-data-jpa` | None |
| HSQLDB | `hsqldb,spring-data-jpa` | None |
| MySQL | `mysql,spring-data-jpa` | `docker-compose --profile mysql up` |
| PostgreSQL | `postgres,spring-data-jpa` | `docker-compose --profile postgres up` |

The repository layer (`jdbc` / `jpa` / `spring-data-jpa`) is the second part of the profile pair and can be swapped independently.

---

## Testing

```bash
# Run all tests + enforce JaCoCo coverage gates
./mvnw verify

# Run only unit/integration tests (skip coverage enforcement)
./mvnw test
```

### Test structure

| Test class / folder | What it tests |
|---|---|
| `rest/controller/*Tests.java` | Controller slice tests using `MockMvc` + `@MockitoBean` for the service layer |
| `service/clinicService/AbstractClinicServiceTests.java` | Abstract base with full service integration tests |
| `service/clinicService/ClinicService{H2Jdbc,HsqlJdbc,Jpa,SpringDataJpa}Tests` | Concrete runs against each repo implementation |
| `service/userService/*` | Same pattern for `UserService` |
| `validation/PetAgeValidatorTest.java` | Unit test for custom `PetAgeValidator` |
| `test/jmeter/` | JMeter benchmark plan (run separately, not part of `mvn test`) |
| `test/postman/` | Newman/Postman non-regression tests (run via `./postman-tests.sh`) |

### Coverage requirements (enforced by JaCoCo)

- **Line coverage:** ≥ 85%
- **Branch coverage:** ≥ 66%
- Excluded from coverage: `rest/dto/**` and `rest/api/**` (generated code)

### Controller test pattern

Tests use `@SpringBootTest` + `@ContextConfiguration(classes = ApplicationTestConfig.class)` + `@WebAppConfiguration`. The service layer is mocked with `@MockitoBean`. `MockMvc` is built manually from the controller under test plus `ExceptionControllerAdvice`. Role-based access is tested with `@WithMockUser`.

---

## API Design

- **API-first:** the contract lives in `src/main/resources/openapi.yml` (OAS 3.1). Code is generated from it, not the other way around.
- When adding or changing endpoints, **edit `openapi.yml` first**, then regenerate and implement the new interface method.
- V2 controllers live in `rest/controller/v2/` and extend V1 behaviour with pagination.
- All controllers implement a generated `*Api` interface — never add request mappings directly to the controller class.

---

## Security

Security is **disabled by default** (`petclinic.security.enable=false`).

Enable Basic Auth:
```properties
# src/main/resources/application.properties
petclinic.security.enable=true
```

Default admin: `admin` / `admin`.

| Role | Permitted controllers |
|---|---|
| `OWNER_ADMIN` | `OwnerController`, `PetController`, `PetTypeController` (read), `VisitController` |
| `VET_ADMIN` | `PetTypeController`, `SpecialityController`, `VetController` |
| `ADMIN` | `UserController` |

---

## Code Conventions

- **Formatting:** spaces (4-space indent for `.java` and `.xml`), LF line endings, UTF-8 — enforced by `.editorconfig`.
- **No trailing whitespace** in `.java` and `.xml` files.
- **Apache 2.0 licence header** on every source file.
- **MapStruct** for all model↔DTO mapping — never map fields manually in controllers.
- **`ClinicService`** is the only entry point into the data layer from controllers — do not inject repositories directly into controllers.
- **`@Transactional`** belongs on service methods or controller methods where write operations span multiple repository calls.
- **`@PreAuthorize`** annotations on controller methods control role-based access — keep them aligned with the role table above.

---

## CI

GitHub Actions workflow: `.github/workflows/ci.yml`

- Triggers on push/PR to `main` or `master`
- Matrix: Java 21 and 24
- Runs `./mvnw --no-transfer-progress verify` (build + test + coverage check)
- Uploads JaCoCo XML report and Surefire results as artifacts (Java 21 run)
- Uses `actions/checkout@v5`, `actions/setup-java@v5`, `actions/upload-artifact@v5` (Node 24-based)

---

## Training Context

This project is the **backend scenario** for the AIFSD 101 DevSecOps bootcamp. The following artefacts are intentionally absent and built by participants during the course:

- CI/CD pipeline beyond the basic workflow above
- SonarQube / SonarCloud quality gate integration
- Docker image build and publish workflow
- Container security scanning
