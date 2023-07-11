#!/bin/bash
PROFILE=${PROFILE:-dev}
ENV=${ENV:-null}
ENTITY=${ENV:-ENTITY}

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
            --profile)
                PROFILE=${2}; shift 2
            ;;    
            --env)
                ENV=${2}; shift 2
            ;;      
            --entity)
                ENTITY=${2}; shift 2
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


installArgoCd() {
    ARGO_PROFILE=argo-${PROFILE}
    ARGO_CHART_DIR=./${ARGO_PROFILE}/helm-charts
    git clone -b main https://github.com/paas2/${ARGO_PROFILE}

    kubectl create ns argocd
    kubectl label namespace argocd istio-injection=enabled --overwrite


    helm dependency update ${ARGO_PROFILE}/helm-charts
    
    helm upgrade argocd \
       ${ARGO_CHART_DIR} \
    -f ${ARGO_CHART_DIR}/values-base.yaml \
    -f ${ARGO_CHART_DIR}/${ENTITY}/values-${ENV}.yaml \
    --namespace argocd \
    --install   

    rm -rf argo-${PROFILE}
}

main () {
    echo -e "\nRunning"  
    echo "PROFILE:  ${PROFILE}"          
    echo "ENV:  ${ENV}"  
    echo "ENTITY:  ${ENTITY}"                         
   
    installArgoCd 
}

processOptions $*
main

