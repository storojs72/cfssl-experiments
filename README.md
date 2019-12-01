# cfssl-experiments

# Certificate Authority

- Typical initialization of new CA:

cfssl gencert -initca configuration/root-ca.json | cfssljson -bare ca

- Typical run CA server:

cfssl serve -ca-key ca-key.pem -ca ca.pem -config configuration/config.json -address 165.227.231.121 -disable revoke,gencrl,bundle,newkey,scaninfo,init_ca,certinfo,scan,crl,ocspsign,authsign,sign

- Typical run OCSP server:

cfssl ocspserve -port 8889 -address 165.227.231.121 -db-config configuration/postgres-config.json


# Client

- Typical request of certificate (API) - get csr, key, crt from remote:

curl -d @request.conf 165.227.231.121:8888/api/v1/cfssl/newcert | cfssljson

- Typical local key generation (generates csr, key):

cfssl genkey config/config-client-csr.json | cfssljson -bare client

- Typical signing csr by remote CA - get crt from remote:

cfssl sign -remote 165.227.231.121 client.csr | cfssljson -bare client




- browse certificate details:

openssl x509 -in client.pem -text -noout

- browse csr details:

openssl req -in client.pem -text -noout

- check ocsp:

openssl ocsp -issuer intermediate-ca.pem -cert client.pem -text -url http://165.227.231.121:8889


### DOCKER

##### ON CFSSL REMOTE HOST



install docker

1) deploy postgres db for certificates storing
- docker pull postgres
- docker run -p 5432:5432 -e POSTGRES_USER=cfssl -e POSTGRES_PASSWORD=cfssl --name postgres -d postgres:latest

1) build cfssl image
- docker build -t cfssl:experiments .

2) migrate cfssl to postgres
- docker run --network host --entrypoint goose cfssl:experiments -path certdb/pg/ -env cfssl-experiments up

2) generate certificates:
- docker run --rm --name cfssl -v "$(pwd)"/cfssl-experiments/:/cfssl cfssl:experiments gencert -loglevel=2 -initca /cfssl/configuration/ca/ca_subj.json > cfssl-experiments/ca.json
- docker run --rm --name cfssl -v "$(pwd)"/cfssl-experiments/:/cfssl --entrypoint cfssljson cfssl:experiments -f /cfssl/ca.json -bare /cfssl/ca

3) run remote cfssl service
- docker run -d --name cfssl --network host -v "$(pwd)"/cfssl-experiments/:/cfssl cfssl:experiments serve -ca /cfssl/ca.pem -ca-key /cfssl/ca-key.pem -config /cfssl/configuration/ca/ca_auth.json -address 178.62.65.214 -db-config /cfssl/configuration/ca/postgres.json
