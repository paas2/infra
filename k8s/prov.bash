#!/bin/bash

VALUES_FILE=${VALUES_FILE:-null}
LB_ADRESSES=${LB_ADRESSES:-192.168.100.85-192.168.100.98}
PROFILE=${PROFILE:-dev}

errorExit () {
    echo -e "\nERROR: $1"; echo
    exit 1
}

usage () {
    cat << END_USAGE
 <options>
--f                 : [required] A git repo for application
--lb                : [optional] Adresses for load balancers
END_USAGE

    exit 1
}

processOptions () {
    # if [ $# -eq 0 ]; then
    #     usage
    # fi

    while [[ $# > 0 ]]; do
        case "$1" in
            --f)
                VALUES_FILE=${2}; shift 2
            ;;
            --lb)
                LB_ADRESSES=${2}; shift 2
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

startMinikube() {
  minikube start \
    --profile "${PROFILE}" \
    --addons registry \
    --addons ingress \
    --addons metallb \
    --disk-size 40G \
    --memory 6G \
    --driver virtualbox

  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: metallb-system
  name: config
data:
  config: |
    address-pools:
    - name: default
      protocol: layer2
      addresses: ["${LB_ADRESSES}"]
EOF
}

installArgoCd() {
    helm repo add argo https://argoproj.github.io/argo-helm
    helm upgrade --install argocd \
    --namespace=argocd \
    --create-namespace \
    -f ${VALUES_FILE}
}

main () {
    echo -e "\nRunning"

    echo "VALUES_FILE:  ${VALUES_FILE}"
    echo "LB_ADRESSES:  ${LB_ADRESSES}"       

    startMinikube   
    installArgoCd 
}


processOptions $*
main

