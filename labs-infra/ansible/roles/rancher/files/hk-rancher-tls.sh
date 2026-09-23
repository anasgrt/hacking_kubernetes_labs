#!/usr/bin/env bash
# Managed by Ansible — the lab CA and Rancher's serving certificate.
#
# Rancher is installed with ingress.tls.source=secret, so it needs a real
# certificate rather than cert-manager. The CA persists across configure runs:
# rotating it would silently invalidate the trust a browser and every imported
# cluster's agent already established. Only the leaf is renewed, and only when
# it is missing, mismatched or close to expiry.
#
# Prints a line beginning "changed:" when it alters anything, which is what
# Ansible reads to decide whether the task changed the host.
set -euo pipefail
directory=${1:?Supply the TLS directory}
hostname=${2:?Supply the Rancher DNS hostname}
[[ "$directory" == /* && "$hostname" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ ]] || exit 1

umask 077
mkdir -p "$directory"
cd "$directory"

if [[ ! -e ca.crt && ! -e ca.key ]]; then
  openssl req -x509 -newkey rsa:3072 -nodes -sha256 -days 3650 \
    -keyout ca.key -out ca.crt -subj '/CN=Hacking Kubernetes Lab Rancher CA' \
    -addext 'basicConstraints=critical,CA:TRUE' \
    -addext 'keyUsage=critical,keyCertSign,cRLSign'
  echo 'changed: created the lab CA'
fi

# Never silently replace an incomplete, expired or mismatched CA: failing here
# is recoverable from a backup, while a new CA breaks every existing trust.
test -s ca.key && test -s ca.crt
openssl x509 -in ca.crt -checkend 2592000 -noout
test "$(openssl pkey -in ca.key -pubout 2>/dev/null)" = "$(openssl x509 -in ca.crt -pubkey -noout)"

renew=true
if [[ -s tls.crt && -s tls.key ]] &&
   openssl verify -CAfile ca.crt -verify_hostname "$hostname" tls.crt >/dev/null 2>&1 &&
   openssl x509 -in tls.crt -checkend 2592000 -noout >/dev/null &&
   [[ "$(openssl pkey -in tls.key -pubout 2>/dev/null)" == "$(openssl x509 -in tls.crt -pubkey -noout)" ]]; then
  renew=false
fi

if "$renew"; then
  staging=$(mktemp -d "$directory/.leaf.XXXXXX")
  trap 'rm -rf "$staging"' EXIT
  openssl req -new -newkey rsa:3072 -nodes -keyout "$staging/tls.key" \
    -out "$staging/tls.csr" -subj "/CN=$hostname"
  printf 'subjectAltName=DNS:%s\nbasicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\n' \
    "$hostname" > "$staging/extensions"
  openssl x509 -req -in "$staging/tls.csr" -CA ca.crt -CAkey ca.key \
    -set_serial "0x$(openssl rand -hex 16)" -days 365 -sha256 \
    -extfile "$staging/extensions" -out "$staging/tls.crt"
  openssl verify -CAfile ca.crt -verify_hostname "$hostname" "$staging/tls.crt"
  mv "$staging/tls.key" tls.key
  mv "$staging/tls.crt" tls.crt
  echo 'changed: issued the Rancher certificate'
fi
