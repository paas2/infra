#!/bin/bash

set -ex

cert_dir=`dirname "$BASH_SOURCE"`/../certs

echo "Clean up contents of dir ${cert_dir}"
rm -rf ${cert_dir}/intermediate

echo "Generating new certificates"
mkdir -p ${cert_dir}/intermediate

if ! [ -x "$(command -v step)" ]; then
  echo 'Error: Install the smallstep cli (https://github.com/smallstep/cli)'
  exit 1
fi

# step certificate create root.paas2 ${cert_dir}/root-cert.pem ${cert_dir}/root-ca.key \
#   --profile root-ca --no-password --insecure --san root.paas2 \
#   --not-after 87600h --kty RSA 

step certificate create intermediate.paas2 ~/ca-cert.pem ~/ca-key.pem --ca ${cert_dir}/root-cert.pem --ca-key ${cert_dir}/root-ca.key --profile intermediate-ca --not-after 8760h --no-password --insecure --san intermediate.paas2 --kty RSA 

cat ~/ca-cert.pem ~/root-cert.pem > ~/cert-chain.pem