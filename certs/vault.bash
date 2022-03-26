#!/bin/bash

PROFILE=${PROFILE:-dev}
XPATH

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
    
    XPATH=paas2/k8s/${PROFILE}

    echo "PROFILE:  ${PROFILE}"  
    echo "PATH:  ${XPATH}"   
    

    # installVault
    getReviewerJWTToken
    getKubeCertAndHost
    enableKubeAuth
    configureKubeAuth
    createPolicy
    createRoleAndAttachPolicy
    createCertificates
    saveCertificatesToVault

    # read var1 var2 var3 <<< $(echo $(curl -s 'https://api.github.com/repos/torvalds/linux' |  jq -r '.id, .name, .full_name'))  
    # # read -r var1 var2 <<< "Hello, World!"

    # echo "id        : $var1"
    # echo "name      : $var2"
    # echo "full_name : $var3"          
}

getReviewerJWTToken() {
    export VAULT_SA_NAME=$(kubectl -n argocd get sa argocd-repo-server --output jsonpath="{.secrets[*]['name']}")
    export SA_JWT_TOKEN=$(kubectl -n argocd get secret $VAULT_SA_NAME --output 'go-template={{ .data.token }}' | base64 --decode)
    echo $SA_JWT_TOKEN > ~/cluster-jwt-token
}

getKubeCertAndHost(){
    KUBE_CA_CERT=$(kubectl --context=${PROFILE} config view --raw --minify --flatten --output='jsonpath={.clusters[].cluster.certificate-authority-data}' | base64 --decode)
    echo $KUBE_CA_CERT > ~/cluster-ca.crt   
    KUBE_HOST=$(kubectl --context=${PROFILE} config view --minify | grep server | cut -f 2- -d ":" | tr -d " ") 
    echo $KUBE_HOST > ~/cluster-kube-host     
}

enableKubeAuth() {
    # kubectl port-forward helm-vault-0 8200:8200 -n vault --context="security-dev" 
    export VAULT_ADDR='http://127.0.0.1:8200'
    # export VAULT_TOKEN=$(cat vault-cluster-keys.json | jq -r ".root_token")     
    vault login token=$(cat ./vault-cluster-keys.json | jq -r ".root_token")  
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

    vault write auth/${XPATH}/role/vprole \
        bound_service_account_names=* \
        bound_service_account_namespaces=* \
        policies=${PROFILE} \
        ttl=24h
}

createCertificates() {
    # Step 1: Generate root CA
        # Enable the pki secrets engine at the pki path.
    # vault secrets enable pki

    #     # Tune the pki secrets engine to issue certificates with a maximum time-to-live (TTL) of 87600 hours - 10 years
    # vault secrets tune -max-lease-ttl=87600h pki

    #     # Generate the root certificate and save the certificate in CA_cert.crt.
    #     # This generates a new self-signed CA certificate and private key. 
    #     # Vault will automatically revoke the generated root at the end of its lease period (TTL); 
    #     # the CA certificate will sign its own Certificate Revocation List (CRL).
    # vault write -field=certificate pki/root/generate/internal \
    #     common_name="paas2.com" \
    #     ttl=87600h > CA_cert.crt

    #     # Configure the CA and CRL URLs.
    # vault write pki/config/urls \
    #     issuing_certificates="$VAULT_ADDR/v1/pki/ca" \
    #     crl_distribution_points="$VAULT_ADDR/v1/pki/crl"


    # Step 2: Generate intermediate CA
        # Now, you are going to create an intermediate CA using the root CA you regenerated in the previous step.

        # First, enable the pki secrets engine at the pki_int path.        
    # vault secrets enable -path=pki_int pki        

        # Tune the pki_int secrets engine to issue certificates with a maximum time-to-live (TTL) of 43800 hours.
    # vault secrets tune -max-lease-ttl=43800h pki_int

    
        # Configure a role that maps a name in Vault to a procedure for generating a certificate. 
        # When users or machines generate credentials, they are generated against this role:

    vault write pki/roles/${PROFILE} \
        allowed_domains=paas2.com \
        allow_subdomains=true \
        max_ttl=72h

        # Execute the following command to generate an intermediate and save the CSR as pki_intermediate.csr
    
    # vault write -format=json pki/issue/${PROFILE} \
    #     common_name=www.paas2.com

    # vault write -format=json pki/issue/bwb-dev \
    #     common_name="www.paas2.com" > pki_intermediate.csr 

    read certificate issuing_ca private_key <<< $(echo $(vault write -format=json pki/issue/${PROFILE} common_name="www.paas2.com" | 
      jq -r '.data.certificate, .data.issuing_ca, .data.private_key')) 



    echo certificate > ~/ca-cert.pem
    echo issuing_ca > ~/root-cert.pem    
    echo private_key > ~/ca-key.pem        

    cat ~/ca-cert.pem ~/root-cert.pem > ~/cert-chain.pem

    # vault write pki_int/intermediate/generate/internal common_name=ibm.com ttl=8760h        

        # Sign the intermediate certificate with the root CA private key, and save the generated certificate as intermediate.cert.pem    
    # vault write -format=json pki/root/sign-intermediate csr=@pki_intermediate.csr \
    #     format=pem_bundle ttl="43800h" \
    #     | jq -r '.data.certificate' > intermediate.cert.pem

    #     # Once the CSR is signed and the root CA returns a certificate, it can be imported back into Vault.      
    # vault write pki_int/intermediate/set-signed certificate=@intermediate.cert.pem          


    # sh ../certs/generate-certificates.sh
}

saveCertificatesToVault() {
    vault secrets enable -path=${XPATH} kv-v2
    jq -Rs '{ pem: . }' ~/ca-cert.pem | vault kv put ${XPATH}/certs/ca-cert.pem  -
    jq -Rs '{ pem: . }' ~/ca-key.pem | vault kv put ${XPATH}/certs/ca-key.pem  -
    jq -Rs '{ pem: . }' ~/cert-chain.pem | vault kv put ${XPATH}/certs/cert-chain.pem  -
    jq -Rs '{ pem: . }' ~/root-cert.pem | vault kv put ${XPATH}/certs/root-cert.pem  -         
}


processOptions $*
main

