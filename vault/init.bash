#!/bin/bash

# should run at most once per environment

ENV=${ENV:-dev}

errorExit () {
    echo -e "\nERROR: $1"; echo
    exit 1
}

usage () {
    cat << END_USAGE
 <options>
--env : [required] environment - such as dev, sit, uat
END_USAGE

    exit 1
}

processOptions () {
    while [[ $# > 0 ]]; do
        case "$1" in      
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
    ./login.bash --env ${ENV}       
    
    export $(grep -v '^#' .${ENV}.env | xargs)
    
    

    enableKV2Engine
    saveGitCredentials
    enablePKIEngine
    createSharedPathReadPolicy
}

enableKV2Engine() {
    vault secrets enable -path ${SAHAB_KV_PATH} -version=2 kv     
}

saveGitCredentials() {
    vault kv put ${SAHAB_KV_PATH}/GitHub sshPrivateKey=$(echo $(cat ~/.ssh/id_ed25519 | base64)) url=$(echo "git@github.com:paas2" | base64) 
}

enablePKIEngine() {
    vault secrets enable -path ${SAHAB_PKI_PATH} pki  
    vault secrets tune -max-lease-ttl=87600h ${SAHAB_PKI_PATH}
    
    vault write -field=certificate ${SAHAB_PKI_PATH}/root/generate/internal \
        common_name="${ENV}.sahab2.com" \
        ttl=87600h > ca_${ENV}_cert.crt   

    vault write ${SAHAB_PKI_PATH}/config/urls \
        issuing_certificates="$VAULT_ADDR/v1/${SAHAB_PKI_PATH}/ca" \
        crl_distribution_points="$VAULT_ADDR/v1/${SAHAB_PKI_PATH}/crl"              
}

createSharedPathReadPolicy() {
    echo -e "\crate shared read policy"

    vault policy write ${SAHAB_SHARED_POLICY_NAME} - <<EOF
    path "${SAHAB_KV_PATH}/data/${SAHAB_SHARED_KV_PATH}/*" {
        capabilities = ["read"]
    }
EOF

}

processOptions $*
main

