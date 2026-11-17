#!/usr/bin/env bash
# Generates a self-signed certificate for the lab (localhost only - never use in production).
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p certs
if [[ -f certs/lab.pem && "${1:-}" != "--force" ]]; then
  echo "certs/lab.pem already exists (use --force to regenerate)"
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
  -keyout "$tmp/key.pem" -out "$tmp/cert.pem" \
  -subj "/CN=localhost/O=Secure Proxy Failover Lab" \
  -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" 2>/dev/null

# HAProxy expects certificate + private key in a single file.
cat "$tmp/cert.pem" "$tmp/key.pem" > certs/lab.pem
# Readable by the non-root haproxy user inside the container. Lab key only.
chmod 644 certs/lab.pem
echo "Created certs/lab.pem (self-signed, valid 365 days)"
