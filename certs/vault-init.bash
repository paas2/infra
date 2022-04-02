#!/bin/bash

main () {
    echo -e "\nRunning"

    SAHAP2_KV_PATH=sahap2-kv
    SAHAP2_PKI_PATH=sahap2-pki  
    SAHAP2_K8S_AUTH_SHARED_PAHT=sahap2-shared

    SAHAP2_SHARED_KV_PATH=shared
    SAHAP2_SHARED_POLICY_NAME=sahap2-shared-read

    login
    enableKV2Engine   
    enablePKI 
    # enableKubeAuth
    createSharedPathReadPolicy
}

login(){
    export VAULT_ADDR='http://192.168.99.172:31640'    
    vault login token=$(cat ./vault-cluster-keys.json | jq -r ".root_token")
}

enableKV2Engine() {
    vault secrets enable -path ${SAHAP2_KV_PATH} -version=2 kv     
}

enablePKI() {
    # Enable the pki secrets engine at the pki path.
    vault secrets enable -path ${SAHAP2_PKI_PATH} pki  
     
     # vault secrets tune -max-lease-ttl=87600h pki

    vault secrets tune -max-lease-ttl=87600h ${SAHAP2_PKI_PATH}

    # Generate the root certificate and save the certificate in CA_cert.crt.
    # This generates a new self-signed CA certificate and private key. 
    # Vault will automatically revoke the generated root at the end of its lease period (TTL); 
    # the CA certificate will sign its own Certificate Revocation List (CRL). 

    vault write -field=certificate ${SAHAP2_PKI_PATH}/root/generate/internal \
        common_name="paas2.com" \
        ttl=87600h > CA_cert.crt    


    # Configure the CA and CRL URLs.
    vault write ${SAHAP2_PKI_PATH}/config/urls \
        issuing_certificates="$VAULT_ADDR/v1/${SAHAP2_PKI_PATH}/ca" \
        crl_distribution_points="$VAULT_ADDR/v1/${SAHAP2_PKI_PATH}/crl"              
}

# enableKubeAuth() {  
#     echo -e "\enableKubeAuth"
#     vault auth enable --path=${SAHAP2_K8S_AUTH_SHARED_PAHT} kubernetes  
# }

createSharedPathReadPolicy() {
    echo -e "\createPolicy"

    vault policy write ${SAHAP2_SHARED_POLICY_NAME} - <<EOF
    path "${SAHAP2_KV_PATH}/data/${SAHAP2_SHARED_KV_PATH}/*" {
        capabilities = ["read"]
    }
EOF

}

main

