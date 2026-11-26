#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
exec mvn -B -ntp -DskipTests package cargo:run "$@"
