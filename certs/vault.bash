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

    # K8S_AUTH_PROFILE_PATH=paas2-${PROFILE}  
    # K8S_AUTH_SHARED_PATH=paas2-shared 
    # KV_PATH=paas2-kv 
    # K8_COMMON_KV_PATH=clusters/common

    SAHAP2_K8S_AUTH_PROFILE_PATH=sahap2-${PROFILE}  
    
    SAHAP2_KV_PATH=sahap2-kv
    SAHAP2_PKI_PATH=sahap2-pki  
    SAHAP2_K8S_AUTH_SHARED_PAHT=sahap2-shared

    SAHAP2_SHARED_KV_PATH=shared
    SAHAP2_SHARED_POLICY_NAME=sahap2-shared-read  

    
    login
    enableKubeAuth
    configureKubeAuth    
    createPolicy
    createRoleAndAttachPolicy
    saveK8SInfo
    createCertificates
    saveCertificatesToVault        
}

login(){
    echo -e "\login"
    
    export VAULT_ADDR='http://192.168.99.172:31640'    
    vault login token=$(cat ./vault-cluster-keys.json | jq -r ".root_token")  
}

enableKubeAuth() {  
    echo -e "\enableKubeAuth"
    vault auth enable --path=${SAHAP2_K8S_AUTH_PROFILE_PATH} kubernetes  
}

configureKubeAuth(){
    
    echo -e "\configureKubeAuth"

    export VAULT_SA_NAME=$(kubectl --context=${PROFILE} -n argocd get sa argocd-repo-server --output jsonpath="{.secrets[*]['name']}")
    export SA_JWT_TOKEN=$(kubectl --context=${PROFILE} -n argocd get secret $VAULT_SA_NAME --output 'go-template={{ .data.token }}' | base64 --decode)
    KUBE_HOST=$(kubectl --context=${PROFILE} config view --minify | grep server | cut -f 2- -d ":" | tr -d " ") 
    KUBE_CA_CERT_DECODED=$(kubectl --context=${PROFILE} config view --raw --minify --flatten --output='jsonpath={.clusters[].cluster.certificate-authority-data}' | base64 --decode)
    KUBE_CA_CERT=$(kubectl --context=${PROFILE} config view --raw --minify --flatten --output='jsonpath={.clusters[].cluster.certificate-authority-data}')

    vault write auth/${SAHAP2_K8S_AUTH_PROFILE_PATH}/config \
    token_reviewer_jwt=${SA_JWT_TOKEN} \
    kubernetes_host=${KUBE_HOST} \
    kubernetes_ca_cert="${KUBE_CA_CERT_DECODED}" \
    issuer="https://kubernetes.default.svc.cluster.local"          
}

saveK8SInfo() {
    echo "{ \"certificate-authority-data\":\"${KUBE_CA_CERT}\", \
    \"server\": \"${KUBE_HOST}\",\
    \"sa-token\":\"${SA_JWT_TOKEN}\" }" | vault kv put ${SAHAP2_KV_PATH}/${SAHAP2_SHARED_KV_PATH}/${PROFILE} - 
}

createPolicy() {
    echo -e "\createPolicy"

    vault policy write ${PROFILE}-read - <<EOF
    path "${SAHAP2_KV_PATH}/data/${PROFILE}/*" {
        capabilities = ["read"]
    }
EOF
}

createRoleAndAttachPolicy() {
    
    echo -e "\createRoleAndAttachPolicy"

    vault write auth/${SAHAP2_K8S_AUTH_PROFILE_PATH}/role/${PROFILE} \
        bound_service_account_names=argocd-repo-server \
        bound_service_account_namespaces=argocd \
        policies=${PROFILE}-read \
        policies=${SAHAP2_SHARED_POLICY_NAME} \
        ttl=24h
}

createCertificates() {
    
    echo -e "\createCertificates"

    # Configure a role that maps a name in Vault to a procedure for generating a certificate. 
    # When users or machines generate credentials, they are generated against this role:

    vault write ${SAHAP2_PKI_PATH}/roles/${PROFILE} \
        allowed_domains=paas2.com \
        allow_subdomains=true \
        max_ttl=72h   

    MY_NEW_CERT=$(vault write -format=json ${SAHAP2_PKI_PATH}/issue/${PROFILE} common_name="www.paas2.com")

    jq '.data.certificate' <<< $MY_NEW_CERT  > ~/ca-cert.pem
    jq '.data.issuing_ca' <<< $MY_NEW_CERT  > ~/root-cert.pem    
    jq '.data.private_key' <<< $MY_NEW_CERT > ~/ca-key.pem        

    cat ~/ca-cert.pem ~/root-cert.pem > ~/cert-chain.pem
}

saveCertificatesToVault() {  
    
    echo -e "\saveCertificatesToVault"

    echo "{ \"ca-cert\":\"$(cat ~/ca-cert.pem | base64)\", \
    \"ca-key\": \"$(cat ~/ca-key.pem | base64)\",\
    \"root-cert\":\"$(cat ~/root-cert.pem | base64)\",\
    \"cert-chain\":\"$(cat ~/cert-chain.pem | base64)\" }" | vault kv put ${SAHAP2_KV_PATH}/${PROFILE}/cacerts -     
}




processOptions $*
main

