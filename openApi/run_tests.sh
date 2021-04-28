#!/bin/bash

# this script will generate one bulk script an run dredd tests
#speccy resolve -o openapi_all.yaml openapi.yaml
openapi-generator-cli generate -i openapi.yaml -g openapi-yaml -o yaml/
dredd