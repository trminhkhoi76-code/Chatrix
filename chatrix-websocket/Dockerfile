# ── Build ─────────────────────────────────────────────────────────────────────
FROM maven:3-eclipse-temurin-17 AS build

WORKDIR /workspace

# Cache dependencies before copying source (layer is reused unless pom changes)
COPY pom.xml .
COPY chatrix-websocket/pom.xml chatrix-websocket/
RUN mvn -B -pl chatrix-websocket -am dependency:go-offline -q

COPY chatrix-websocket/src chatrix-websocket/src
RUN mvn -B -pl chatrix-websocket -am package -DskipTests -q

# ── Runtime ───────────────────────────────────────────────────────────────────
FROM eclipse-temurin:17-jre-alpine

RUN addgroup -S chatrix && adduser -S chatrix -G chatrix
USER chatrix

WORKDIR /app
COPY --from=build /workspace/chatrix-websocket/target/*-jar-with-dependencies.jar app.jar

EXPOSE 8081
ENTRYPOINT ["java", "-jar", "app.jar"]