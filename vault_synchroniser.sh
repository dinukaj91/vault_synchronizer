#!/usr/bin/env bash

function cleanup {
    rm -rf path_list new_path_list json_files_list json_files
}

function traverse {
    local -r path="$1"

    result=$(vault kv list -format=json $path 2>&1)

    status=$?
    if [ ! $status -eq 0 ];
    then
        if [[ $result =~ "permission denied" ]]; then
            return
        fi
        >&2 echo "$result"
    fi

    for secret in $(echo "$result" | jq -r '.[]'); do
        if [[ "$secret" == */ ]]; then
            traverse "$path$secret"
        else
            echo "$path$secret"
        fi
    done
}

function call_traverse {
    echo "Creating file with secret paths...."
    if [[ "$1" ]]; then
        # Make sure the path always end with '/'
        vaults=("${1%"/"}/")
    else
        vaults=$(vault secrets list -format=json | jq -r 'to_entries[] | select(.value.type =="kv") | .key')
    fi

    for vault in $vaults; do
        traverse $vault > path_list
    done
}

function sanitize_secret_paths {
    echo "Removing production and staging paths from list...."
    cat path_list | grep -E "development|prenv|/pr/" > new_path_list
}

function get_key_value_pairs {
    echo "Generating json files with key/value pairs...."
    mkdir -p json_files
    input="new_path_list"
    while IFS= read -r new_path
    do
        KEY_VALUE_JSON_MAP=$(vault kv get -format=json $new_path | jq .data)
        json_file_name=${new_path//\//.}
        echo $KEY_VALUE_JSON_MAP > json_files/$json_file_name.json
    done < "$input"
}

function update_development_vault {
    echo "Updating New Vault...."
    for json_file in "json_files"/*
    do
        vault_path=${json_file//.//}
        vault_path=${vault_path//json_files\/}
        vault_path=${vault_path///json}
        vault_path=$(echo "kv/$vault_path")
        echo "$vault_path"
        vault kv put $vault_path @$json_file
    done
}

# Add Source Vault
export VAULT_ADDR=XXXXXXXXXXXXXX
export VAULT_TOKEN=XXXXXXXXXXXXXXX
cleanup
call_traverse secret
sanitize_secret_paths
get_key_value_pairs
# Add Destination Vault
export VAULT_ADDR=XXXXXXXXXXXXXX
export VAULT_TOKEN=XXXXXXXXXXXXXX
update_development_vault
cleanup