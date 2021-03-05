#!/bin/bash

# this script will generate one bulk script an run dredd tests
speccy resolve -o openapi_all.yaml openapi.yaml
dredd