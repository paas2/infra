#!/bin/bash

main () {
    echo -e "\nRunning"
    kubectl -n vault exec vault-0 -- vault operator init -key-shares=1 -key-threshold=1 -format=json > cluster-keys.json
    VAULT_UNSEAL_KEY=$(cat cluster-keys.json | jq -r ".unseal_keys_b64[]")

    kubectl -n vault exec vault-0 -- vault operator unseal $VAULT_UNSEAL_KEY
}

main

