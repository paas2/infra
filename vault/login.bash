#!/bin/bash

ENV=${ENV:-dev}

errorExit () {
    echo -e "\nERROR: $1"; echo
    exit 1
}

usage () {
    cat << END_USAGE
 <options>
--env               : [required] environment - such as dev, sit, uat
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

login () {
    echo -e "\loging"

    # source .${ENV}.env
    export $(grep -v '^#' .${ENV}.env | xargs)
    vault login token="${VAULT_TOKEN}"
}
login

