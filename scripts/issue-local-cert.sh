#!/bin/sh
# Run on the trusted PC; copy only myfinance.crt and myfinance.key to the VM.
set -eu
umask 077
pki_dir=${1:-.local-pki}
mkdir -p "$pki_dir"
cd "$pki_dir"

if [ ! -f root-ca.key ] && [ ! -f root-ca.crt ]; then
    openssl req -x509 -newkey rsa:3072 -nodes -sha256 -days 3650 \
        -keyout root-ca.key -out root-ca.crt \
        -subj '/CN=MyFinance Local Root CA' \
        -addext 'basicConstraints=critical,CA:TRUE,pathlen:0' \
        -addext 'keyUsage=critical,keyCertSign,cRLSign' \
        -addext 'subjectKeyIdentifier=hash'
fi
if [ ! -f root-ca.key ] || [ ! -f root-ca.crt ]; then
    echo 'Par incompleto de chave/certificado da CA. Restaure o backup; a CA não será substituída.' >&2
    exit 1
fi
openssl x509 -in root-ca.crt -checkend 31622400 -noout

work_dir=$(mktemp -d ./issue.XXXXXX)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
cat > "$work_dir/extensions.cnf" <<'EOF'
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:myfinance.com,IP:192.168.100.10
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid,issuer
EOF
openssl req -new -newkey rsa:2048 -nodes -sha256 \
    -keyout "$work_dir/myfinance.key" -out "$work_dir/myfinance.csr" \
    -subj '/CN=myfinance.com'
openssl x509 -req -sha256 -days 365 \
    -in "$work_dir/myfinance.csr" -CA root-ca.crt -CAkey root-ca.key \
    -set_serial "0x$(openssl rand -hex 16)" \
    -extfile "$work_dir/extensions.cnf" -out "$work_dir/myfinance.crt"
openssl verify -CAfile root-ca.crt -purpose sslserver \
    -verify_hostname myfinance.com "$work_dir/myfinance.crt"
openssl verify -CAfile root-ca.crt -purpose sslserver \
    -verify_ip 192.168.100.10 "$work_dir/myfinance.crt"
mv "$work_dir/myfinance.key" myfinance.key
mv "$work_dir/myfinance.crt" myfinance.crt
chmod 644 root-ca.crt myfinance.crt
printf '%s\n' 'Certificado emitido por 365 dias. Guarde a CA e sua chave no PC; não envie root-ca.key à VM.'
