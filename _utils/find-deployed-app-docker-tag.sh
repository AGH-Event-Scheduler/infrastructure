#!/bin/bash

if [[ $# -lt 2 ]]; then
    echo "Provide: resource-group name"
    exit 1
fi

rg=$1
name=$2

result=$(az resource show -g $rg -n $name --resource-type Microsoft.Web/sites 2>&1)

if [[ $? -eq 0 ]]; then
    docker_image_tag=$(echo $result | jq '.properties.siteConfig.linuxFxVersion' | tr -d "\"" | cut -d ":" -f 2)
    echo "{\"docker_image_tag\":\"$docker_image_tag\"}"
    exit 0
fi

echo "{\"docker_image_tag\":null}"
