## OpenAPI generator:
To generate files:
- install `openapi-generator-cli` by command `npm install @openapitools/openapi-generator-cli -g` (nodejs 10 required)
- to generate client run `openapi-generator-cli generate -i openapi.yaml -g python -o client/`
- to generate server run `openapi-generator-cli generate -i openapi.yaml -g python-flask -o server_flask/`
- to generate server run `openapi-generator-cli generate -i openapi.yaml -g python-aiohttp -o server_aiohttp/`
- to generate server run `openapi-generator-cli generate -i openapi.yaml -g cpp-pistache-server -o cpp/`

## available python server generators:
- python-aiohttp
- python-blueplanet
- python-flask

use openapi-generator-cli list to list all available generators (for documentation and other programming languages)

## deploying documentation
copy dist directory from https://github.com/swagger-api/swagger-ui/releases
setup path to openapi.yaml in index.html

## openApi Linter
- npm install speccy -g
- speccy lint openapi.yaml

## another documentation server
speccy serve openapi.yaml

## compose multiple opanApi files to one:
- speccy resolve -j -o openapi_all.yaml openapi.yaml 
## testing
- install dredd by `npm install dredd --global`
- run `./run_tests.sh` in openApi directory (it runs compose to one openApi file and run tests)


 openapi-generator-cli generate -i openapi.yaml -g openapi-yaml -o yaml/