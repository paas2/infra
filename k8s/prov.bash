#!/bin/bash

VALUES_FILE=${VALUES_FILE:-null}
LB_ADRESSES=${LB_ADRESSES:-192.168.100.85-192.168.100.98}
PROFILE=${PROFILE:-dev}
MEMORY=${MEMORY:-8192}
CPUS=${CPUS:-2}
ENV=${ENV:-null}

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
            --memory)
                MEMORY=${2}; shift 2
            ;;  
            --cpus)
                CPUS=${2}; shift 2
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

# added for prometheus operator
# --extra-config kubelet.authentication-token-webhook=true  - This flag enables, that a ServiceAccount token can be used to authenticate against the kubelet(s). This can also be enabled by setting the kubelet configuration value authentication.webhook.enabled to true
# --extra-config kubelet.authorization-mode=Webhook -  This flag enables, that the kubelet will perform an RBAC request with the API to determine, whether the requesting entity (Prometheus in this case) is allowed to access a resource, in specific for this project the /metrics endpoint. This can also be enabled by setting the kubelet configuration value authorization.mode to Webhook
# minikube addons disable metrics-server # The kube-prometheus stack includes a resource metrics API server, so the metrics-server addon is not necessary. Ensure the metrics-server addon is disabled on minikube:

startMinikube() {
  minikube start \
    --profile "${PROFILE}-${ENV}" \
    --addons registry \
    --addons metallb \
    --addons ingress \
    --disk-size 40G \
    --memory ${MEMORY} \
    --cpus ${CPUS} \
    --driver virtualbox \
    --bootstrapper kubeadm \
    --extra-config kubelet.authentication-token-webhook=true \
    --extra-config kubelet.authorization-mode=Webhook \
    --extra-config scheduler.bind-address=0.0.0.0 \
    --extra-config controller-manager.bind-address=0.0.0.0 \
    --extra-config apiserver.enable-admission-plugins=ValidatingAdmissionWebhook \
    --extra-config apiserver.enable-admission-plugins=MutatingAdmissionWebhook \
    --kubernetes-version=v1.23.0

    minikube addons disable metrics-server

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
    sh ./argo.bash --env ${ENV} --profile ${PROFILE}
}

main () {
    echo -e "\nRunning"

    echo "VALUES_FILE:  ${VALUES_FILE}"
    echo "LB_ADRESSES:  ${LB_ADRESSES}"   
    echo "PROFILE:  ${PROFILE}"         
    echo "MEMORY:  ${MEMORY}" 
    echo "CPUS:  ${CPUS}" 
    echo "ENV:  ${ENV}"                       

    startMinikube   
    installArgoCd 
}

processOptions $*
main

