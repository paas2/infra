#!/bin/bash

PROFILE=${PROFILE:-dev}
XPATH=paas2/k8s/${PROFILE}
VAULES_FILE=${VAULES_FILE:-values-injector.yaml}
NAMESPACE=${NAMESPACE:-vault}

errorExit () {
    echo -e "\nERROR: $1"; echo
    exit 1
}

usage () {
    cat << END_USAGE
 <options>
--profile           : [required] profile
--ns                : [optional] namespace
--f                 : [optinal] values file to override defaults. Default is values-injector.yaml
END_USAGE

    exit 1
}

processOptions () {
    while [[ $# > 0 ]]; do
        case "$1" in      
            --profile)
                PROFILE=${2}; shift 2
            ;;  
            --ns)
                NAMESPACE=${2}; shift 2
            ;;  
            --f)
                VAULES_FILE=${2}; shift 2
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
    echo "VAULES_FILE:  ${VAULES_FILE}" 
    echo "NAMESPACE:  ${NAMESPACE}"   
    echo "PATH:  ${XPATH}"   
    

    installVault
    getReviewerJWTToken
    getKubeCertAndHost
    enableKubeAuth
    configureKubeAuth
    createPolicy
    createRoleAndAttachPolicy
    createCertificates
    saveCertificatesToVault
}

installVault() {
    git clone https://github.com/paas2/vault 
    helm upgrade vault ./vault/helm-charts/vault -f ./vault/helm-charts/vault/values.yaml -f ./vault/helm-charts/vault/${VAULES_FILE} --namespace vault --create-namespace --install
}

getReviewerJWTToken() {
    export VAULT_SA_NAME=$(kubectl -n ${NAMESPACE} get sa vault-agent-injector --output jsonpath="{.secrets[*]['name']}")
    export SA_JWT_TOKEN=$(kubectl -n ${NAMESPACE} get secret $VAULT_SA_NAME --output 'go-template={{ .data.token }}' | base64 --decode)
    echo $SA_JWT_TOKEN > ~/cluster-jwt-token
}

getKubeCertAndHost(){
    KUBE_CA_CERT=$(kubectl config view --raw --minify --flatten --output='jsonpath={.clusters[].cluster.certificate-authority-data}' | base64 --decode)
    echo $KUBE_CA_CERT > ~/cluster-ca.crt   
    KUBE_HOST=$(kubectl config view --minify | grep server | cut -f 2- -d ":" | tr -d " ") 
    echo $KUBE_HOST > ~/cluster-kube-host     
}

enableKubeAuth() {
    vault login
    vault auth enable --path=${XPATH} kubernetes
}

configureKubeAuth(){
    vault write auth/${XPATH}/config \
    token_reviewer_jwt="$(cat ~/cluster-jwt-token)" \
    kubernetes_host="$(cat ~/cluster-kube-host)" \
    kubernetes_ca_cert="$(cat ~/cluster-ca.crt)" \
    issuer="https://kubernetes.default.svc.cluster.local"      
}

createPolicy() {
    vault policy write ${PROFILE} - <<EOF
    path "${XPATH}/certs/*" {
        capabilities = ["read"]
    }
EOF
}

createRoleAndAttachPolicy() {
    # vault write auth/${XPATH}/role/${PROFILE} \
    #     bound_service_account_names=default \
    #     bound_service_account_namespaces=default \
    #     policies=dev-app \
    #     ttl=24h    

    vault write auth/${XPATH}/role/${PROFILE} \
        bound_service_account_names=* \
        bound_service_account_namespaces=* \
        policies=${PROFILE} \
        ttl=24h
}

createCertificates() {
    sh ../certs/generate-certificates.sh
}

saveCertificatesToVault() {
    vault secrets enable -path=${XPATH} kv-v2
    jq -Rs '{ pem: . }' ~/ca-cert.pem | vault kv put paas2/k8s/dev/certs/ca-cert.pem  -
    jq -Rs '{ pem: . }' ~/ca-key.pem | vault kv put paas2/k8s/dev/certs/ca-key.pem  -
    jq -Rs '{ pem: . }' ~/ca-chain.pem | vault kv put paas2/k8s/dev/certs/ca-chain.pem  -
    jq -Rs '{ pem: . }' ~/root-cert.pem | vault kv put paas2/k8s/dev/certs/root-cert.pem  -         
}


processOptions $*
main

