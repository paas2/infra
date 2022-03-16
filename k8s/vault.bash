#!/bin/bash

PROFILE=${PROFILE:-dev}

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
    # if [ $# -eq 0 ]; then
    #     usage
    # fi

    while [[ $# > 0 ]]; do
        case "$1" in      
            --profile)
                PROFILE=${2}; shift 2
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

    echo "PROFILE:  ${PROFILE}"           

    configureVault   
}

configureVault() {
    PATH=paas2/k8s/${PROFILE}

    vault login
    vault auth enable --path=${PATH} kubernetes

    # vault write auth/${PROFILE}/config \
    # token_reviewer_jwt="$(cat ~/dev-cluster-jwt-token)" \
    # kubernetes_host=https://192.168.20.22 \
    # kubernetes_ca_cert="$(cat ~/dev-ca.crt)" \
    # issuer="https://kubernetes.default.svc.cluster.local"

    vault secrets enable -path=${PATH} kv-v2
    vault kv put ${PATH}/certs/ca-cert @ca-cert.pem 
    vault kv put ${PATH}/certs/ca-key @ca-key.pem  
    vault kv put ${PATH}/certs/cert-chain @cert-chain.pem    
    vault kv put ${PATH}/certs/root-cert @root-cert.pem     

    vault policy write ${PROFILE} - <<EOF
    path “${PATH}/certs/*” {
        capabilities = ["read"]
    }
EOF

    vault write \
        bound_service_account_names=default \
        bound_service_account_namespaces=default \
        policies=dev-app \
        ttl=24h

}


processOptions $*
main

