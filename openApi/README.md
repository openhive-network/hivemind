## OpenAPI generator:
To generate files:
- install `openapi-generator-cli` by command `npm install @openapitools/openapi-generator-cli -g` (nodejs 10 required)
- to generate client run `openapi-generator-cli generate -i openapi.yaml -g python -o client/`
- to generate server run `openapi-generator-cli generate -i openapi.yaml -g python-flask -o server/`