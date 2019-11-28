# cfssl-experiments

cfssl host: 165.227.231.121


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


#####ON CFSSL REMOTE HOST
1) build container
- docker image build -f docker/Dockerfile . -t cfssl:experiments
