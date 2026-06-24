#!/usr/bin/env bash
set -euo pipefail

: "${OTEL_JAVAAGENT:?Set OTEL_JAVAAGENT to opentelemetry-javaagent.jar}"
: "${OTEL_EXPORTER_OTLP_ENDPOINT:=http://localhost:4318}"
: "${OTEL_EXPORTER_OTLP_PROTOCOL:=http/protobuf}"
: "${OTEL_RESOURCE_ATTRIBUTES:=deployment.environment=demo,service.namespace=java-sample}"

java \
  -javaagent:"${OTEL_JAVAAGENT}" \
  -Dotel.service.name=test-insert \
  -Dotel.exporter.otlp.endpoint="${OTEL_EXPORTER_OTLP_ENDPOINT}" \
  -Dotel.exporter.otlp.protocol="${OTEL_EXPORTER_OTLP_PROTOCOL}" \
  -Dotel.resource.attributes="${OTEL_RESOURCE_ATTRIBUTES},host.name=sample-host-a,service.role=database-writer" \
  -jar test-insert/target/test-insert-0.0.1-SNAPSHOT.jar
