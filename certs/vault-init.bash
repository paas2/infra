#!/bin/bash

PROFILE=${PROFILE:-dev}
ENV=${PROFILE:-dev}

errorExit () {
    echo -e "\nERROR: $1"; echo
    exit 1
}

usage () {
    cat << END_USAGE
 <options>
--profile           : [required] profile
END_USAGE

    exit 1
}

processOptions () {
    while [[ $# > 0 ]]; do
        case "$1" in      
            --profile)
                PROFILE=${2}; shift 2
            ;;  
            --env)
                ENV=${2}; shift 2
            ;;                                                                                                                         
            -h | --help)
                usage
            ;;
            *)
                usage
            ;;
        esac
    done
}

main () {
    echo -e "\nRunning"

    sahab2_KV_PATH=sahab2-kv
    sahab2_PKI_PATH=sahab2-pki  
    sahab2_K8S_AUTH_SHARED_PAHT=sahab2-shared

    sahab2_SHARED_KV_PATH=shared
    sahab2_SHARED_POLICY_NAME=sahab2-shared-read

    login
    enableKV2Engine   
    enablePKI 
    # enableKubeAuth
    createSharedPathReadPolicy
}

login(){

    export VAULT_ADDR='http://127.0.0.1:8200' 
    vault login token="hvs.KA62SGTOmHmwVWvNFmKW0U96"
}

enableKV2Engine() {
    vault secrets enable -path ${sahab2_KV_PATH} -version=2 kv     
}

enablePKI() {
    # Enable the pki secrets engine at the pki path.
    vault secrets enable -path ${sahab2_PKI_PATH} pki  
     
     # vault secrets tune -max-lease-ttl=87600h pki

    vault secrets tune -max-lease-ttl=87600h ${sahab2_PKI_PATH}

    # Generate the root certificate and save the certificate in CA_cert.crt.
    # This generates a new self-signed CA certificate and private key. 
    # Vault will automatically revoke the generated root at the end of its lease period (TTL); 
    # the CA certificate will sign its own Certificate Revocation List (CRL). 

    vault write -field=certificate ${sahab2_PKI_PATH}/root/generate/internal \
        common_name="paas2.com" \
        ttl=87600h > CA_cert.crt    


    # Configure the CA and CRL URLs.
    vault write ${sahab2_PKI_PATH}/config/urls \
        issuing_certificates="$VAULT_ADDR/v1/${sahab2_PKI_PATH}/ca" \
        crl_distribution_points="$VAULT_ADDR/v1/${sahab2_PKI_PATH}/crl"              
}

# enableKubeAuth() {  
#     echo -e "\enableKubeAuth"
#     vault auth enable --path=${sahab2_K8S_AUTH_SHARED_PAHT} kubernetes  
# }

createSharedPathReadPolicy() {
    echo -e "\createPolicy"

    vault policy write ${sahab2_SHARED_POLICY_NAME} - <<EOF
    path "${sahab2_KV_PATH}/data//${sahab2_SHARED_KV_PATH}/*" {
        capabilities = ["read"]
    }
EOF

}

main

