# ── Build ─────────────────────────────────────────────────────────────────────
FROM maven:3-eclipse-temurin-17 AS build

WORKDIR /workspace

# Cache dependencies before copying source (layer is reused unless pom changes)
COPY pom.xml .
COPY chatrix-api/pom.xml chatrix-api/
RUN mvn -B -pl chatrix-api -am dependency:go-offline -q

COPY chatrix-api/src chatrix-api/src
RUN mvn -B -pl chatrix-api -am package -DskipTests -q

# ── Runtime ───────────────────────────────────────────────────────────────────
FROM eclipse-temurin:17-jre-alpine

RUN addgroup -S chatrix && adduser -S chatrix -G chatrix
USER chatrix

WORKDIR /app
COPY --from=build /workspace/chatrix-api/target/*.jar app.jar

EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]