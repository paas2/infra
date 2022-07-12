#!/bin/bash

# should run at most once per environment

ENV=${ENV:-dev}
PROFILE=${PROFILE:-null}

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
    ./login.bash --env ${ENV}    
    
    export $(grep -v '^#' .${ENV}.env | xargs)
    
    # source .${ENV}.env
    
    K8S_AUTH_PROFILE_PATH=sahab2/${ENV}/${PROFILE} 
    CONTEXT=${PROFILE}-${ENV} 

    enableKubeAuth
    configureKubeAuth
    saveK8SInfo
    createPolicy
    createRoleAndAttachPolicy
}

enableKubeAuth() {  
    echo -e "\enableKubeAuth"
    vault auth enable --path=${K8S_AUTH_PROFILE_PATH} kubernetes  
}

configureKubeAuth(){
    
    echo -e "\configureKubeAuth"

    export VAULT_SA_NAME=$(kubectl --context=${CONTEXT} get sa argocd-repo-server -n argocd --output jsonpath="{.secrets[*]['name']}")
    export SA_JWT_TOKEN=$(kubectl --context=${CONTEXT} get secret $VAULT_SA_NAME -n argocd --output 'go-template={{ .data.token }}' | base64 --decode)
    KUBE_HOST=$(kubectl --context=${CONTEXT} config view --minify | grep server | cut -f 2- -d ":" | tr -d " ") 
    KUBE_CA_CERT_DECODED=$(kubectl --context=${CONTEXT} config view --raw --minify --flatten --output='jsonpath={.clusters[].cluster.certificate-authority-data}' | base64 --decode)
    KUBE_CA_CERT=$(kubectl --context=${CONTEXT} config view --raw --minify --flatten --output='jsonpath={.clusters[].cluster.certificate-authority-data}')

    vault write auth/${K8S_AUTH_PROFILE_PATH}/config \
    token_reviewer_jwt=${SA_JWT_TOKEN} \
    kubernetes_host=${KUBE_HOST} \
    kubernetes_ca_cert="${KUBE_CA_CERT_DECODED}" \
    issuer="https://kubernetes.default.svc.cluster.local"          
}

saveK8SInfo() {
    echo "{ \"certificate-authority-data\":\"${KUBE_CA_CERT}\", \
    \"server\": \"${KUBE_HOST}\",\
    \"sa-token\":\"${SA_JWT_TOKEN}\" }" | vault kv put ${SAHAB_KV_PATH}/${SAHAB_SHARED_KV_PATH}/${PROFILE} - 
}

createPolicy() {
    echo -e "\createPolicy"

    vault policy write ${PROFILE}-${ENV}-read - <<EOF
    path "${SAHAB_SHARED_KV_PATH}/data/*" {
        capabilities = ["read"]
    }
    path "${SAHAB_KV_PATH}/data/GitHub" {
        capabilities = ["read"]
    }    
    
EOF
}

createRoleAndAttachPolicy() {
    
    echo -e "\createRoleAndAttachPolicy"

    vault write auth/${K8S_AUTH_PROFILE_PATH}/role/${PROFILE} \
        bound_service_account_names=argocd-repo-server \
        bound_service_account_namespaces=argocd \
        policies=${PROFILE}-${ENV}-read \
        policies=${SAHAB_SHARED_POLICY_NAME} \
        ttl=24h
}

processOptions $*
main

