# cfssl-experiments

This is a variant of CFSSL tool (https://github.com/cloudflare/cfssl) usage for enabling mutually authenticated and encrypted communication (TLS)
between arbitrary client-server application components.

The total scheme can be represented as following:

![image](https://raw.githubusercontent.com/storojs72/cfssl-experiments/master/screenshots/cfssl-private-ca.png)

## Security Notes:

Scheme above tries to follow best security practices:

1) Root Certificate Authority (root CA) is located on Bob's local computer. Private key is hardware-baked with PKCS#11 token.
2) Intermediate Certificate Authority (intermediate CA) uses authentication API. It's impossible for application to get certificate without knowing API key.
3) Application trusts to chain of certificates (self-signed certificate from root CA combined with self-signed certificate from intermediate CA).
4) OCSP verification is enabled.

## Bob's (private CA administrator) work:

1) Installing CFSSL locally (for RootCA)

On this step we will install CFSSL software on local computer.
We will use modified CFSSL version with enabled PKCS#11 functionality support of `gencert` subcommand.
CFSSL doesn't provide this out-of-the-box for some compatibility issues.
More on this: https://github.com/cloudflare/cfssl/issues/563; https://github.com/cloudflare/cfssl/issues/247.

```
[on Bob's local computer]

git clone https://github.com/storojs72/cfssl-experiments && cd cfssl-experiments
git clone https://github.com/cloudflare/cfssl && cd cfssl
git checkout ebe01990a23a309186790f4f8402eec68028f148
git apply ../patches/pkcs11_1.patch
git apply ../patches/pkcs11_2.patch
go mod tidy
go mod vendor
make
make install
cd ..
```

2) Create RootCA.

On this step we will create root CA with hardware-baked key. Note, that it was only tested with SafeNet 5110 tokens.
It is assumed that you have your token installed: 

- a PKCS#11 vendor library (path is `< PATH TO VENDOR LIBRARY FOR TOKEN >`) is presented;
- token is initialized with identification label (`< TOKEN LABEL >`) and User pin-code (`< USER PIN CODE >`).

Pay attention on subject file `configuration/root-ca/root-ca-subj.json` for our root CA. Most fields are rather self-explanatory. `expiry` field specifies how long time the self-signed ceritificate will be valid, while `pathlen` specifies the depth of trusted certificate chain.

```
[on Bob's local computer]

cfssl gencert -pkcs11-module < PATH TO VENDOR LIBRARY FOR TOKEN > -pkcs11-token < TOKEN LABEL > -pkcs11-pin < USER PIN CODE > -loglevel=0 -initca configuration/root-ca/root-ca-subj.json | cfssljson -bare root
```

3) Prerequisites for remote CFSSL service (for IntermediateCA):

On this step we will prepare remote CFSSL service for intermediate CA.
We will keep records of all issued certificates in PostgreSQL database.
You have to specify password to database `< PASSWORD TO CFSSL DATABASE >` used by CFSSL service

```
[on remote host for IntermediateCA]

apt update
apt install docker.io
systemctl start docker
systemctl enable docker

git clone https://github.com/storojs72/cfssl-experiments && cd cfssl-experiments

docker pull postgres:latest
docker run -p 5432:5432 -e POSTGRES_USER=cfssl -e POSTGRES_PASSWORD=< PASSWORD TO CFSSL DATABASE > --name postgres -d postgres:latest

docker build -t cfssl:experiments .
docker run --rm --network host --entrypoint goose cfssl:experiments -path certdb/pg/ -env cfssl-experiments up
```

4) Create IntermediateCA:

On this step we will create credentials (key and certificate) for intermediate CA. Note, that we will use our root CA when
signing certificate for intermediate one. For security reason, private key of intermediate CA is never transferred from the host
on which it was generated.

Pay attention on configuration of root CA file `configuration/root-ca/root-ca-config.json`. We use `intermediate` profile when issuing intermediate CA
self signed certificate. Depth of certificate's chain is decreased to 1.

```
[on remote host for IntermediateCA]

docker run --rm --name cfssl -v "$(pwd)":/cfssl cfssl:experiments genkey -loglevel=2 /cfssl/configuration/intermediate-ca/intermediate-ca-subj.json > intermediate.json
docker run --rm -v "$(pwd)":/cfssl --entrypoint cfssljson cfssl:experiments -f /cfssl/intermediate.json -bare /cfssl/intermediate

[on Bob's local computer]

scp root@< ADDRESS OF REMOTE CFSSL >:/root/cfssl-experiments/intermediate.csr intermediate.csr
cfssl sign -pkcs11-module < PATH TO VENDOR LIBRARY FOR TOKEN > -pkcs11-token < TOKEN LABEL > -pkcs11-pin < USER PIN CODE > -ca root.pem -csr intermediate.csr -loglevel=0 -config configuration/root-ca/root-ca-config.json -profile intermediate configuration/intermediate-ca/intermediate-ca-subj.json | cfssljson -bare intermediate
scp intermediate.pem root@< ADDRESS OF REMOTE CFSSL >:/root/cfssl-experiments/intermediate.pem
```

5) Create OCSP service:

On this step we will create credentials (key and certificate) for OCSP service.
```
[on remote host for IntermediateCA]

docker run --rm -v "$(pwd)":/cfssl cfssl:experiments gencert -loglevel=2 -ca /cfssl/intermediate.pem -ca-key /cfssl/intermediate-key.pem /cfssl/configuration/ocsp/ocsp-subj.json > ocsp.json
docker run --rm -v "$(pwd)":/cfssl --entrypoint cfssljson cfssl:experiments -f /cfssl/ocsp.json -bare /cfssl/ocsp
```

6) Run IntermediateCA service:

On this step we just start serving our CFSSL service for intermediate CA. It will issue certificates for applications.
Access to database is configured in `configuration/migration/postgres.json`, where you have to put db address `< ADDRESS OF CFSSL DATABASE >`
and CFSSL user password `< PASSWORD TO CFSSL DATABASE >`. Your remote CFSSL service is configured via `configuration/intermediate-ca/intermediate_ca_config.json` file.
You have to provide address of CFSSL host `ADDRESS OF REMOTE CFSSL`, and authentication keys for application (server `< HEX API KEY FOR SERVER >` and client `< HEX API KEY FOR CLIENT >`)

```
[on remote host for IntermediateCA]

docker run -d --name cfssl --network host -v "$(pwd)":/cfssl cfssl:experiments serve -loglevel=0 -ca /cfssl/intermediate.pem -ca-key /cfssl/intermediate-key.pem -config /cfssl/configuration/intermediate-ca/intermediate_ca_config.json -address < ADDRESS OF REMOTE CFSSL HOST > -db-config /cfssl/configuration/migration/postgres.json -responder /cfssl/ocsp.pem -responder-key /cfssl/ocsp-key.pem
```

7) Run OCSP service:

On this step we just start serving our OCSP service.

```
[on remote host for IntermediateCA]

docker run -d --name ocsp --network host -v "$(pwd)":/cfssl cfssl:experiments ocspserve -loglevel=0 -address < ADDRESS OF REMOTE CFSSL > -port 8889 -db-config /cfssl/configuration/migration/postgres.json
```

8) Set OCSP responces autoupdate:

On this step we will setup periodical auto-updates for our OCSP service.

```
[on remote host for IntermediateCA]

crontab -e
* * * * *  docker run --rm --network host -v /root/cfssl-experiments:/cfssl cfssl:experiments ocsprefresh -loglevel=0 -db-config /cfssl/configuration/migration/postgres.json -ca /cfssl/intermediate.pem -responder /cfssl/ocsp.pem -responder-key /cfssl/ocsp-key.pem
```

8) Be ready to provide trusted chain of certificates:

On this step we will create a chain of trusted certificates `chainCA.pem`. Our applications will trust to this chain.

```
[on Bob's local computer]

cat root.pem intermediate.pem > chainCA.pem
```


## Alice's (engineer) work:

1) Create application (client and server) that should have mutually-authenticated and encrypted communication. 
For this purpose we will use toy example (written on Go) of client and server provided with CFSSL.

```
git clone https://github.com/storojs72/cfssl-experiments && cd cfssl-experiments
git clone https://github.com/cloudflare/cfssl & cd cfssl
git checkout ebe01990a23a309186790f4f8402eec68028f148
git apply ../patches/revoke-ocsp.patch
cd ..
```

2) Ask Bob for API authentication keys ("auth-key") for server and client and trusted chain of certificates file ("source") for client. Put them into `application/server_auth_config.json` and `application/client_auth_config.json`

3) Run toy server:
```
go run cfssl/transport/example/maserver/server.go -f configuration/application/server_auth_config.json
```

4) Run toy client:
```
go run cfssl/transport/example/maserver/server.go -f configuration/application/server_auth_config.json
```


### Certificates revocation

Bob is able to revoke certificates. This is a set of steps to do it:
- get serial number and authority_key_id of the certificate (if you have access to .pem. Alternatively, it can be retrieved from the database);
- perform revocation;
- (optionally, if OCSP autoupdate is not set on remote CFSSL service) refresh database table with OCSP responses.

```
[on Bob's local computer]

cfssl certinfo -cert server.pem
curl -d '{"serial": "643283264116739598736176251779770164305825300516 < in decimal!!! >","authority_key_id":"2edbc16d39d1d7d07262f1e18dd16bea29310340 < in hex!!! >","reason":"superseded"}' < ADDRESS OF REMOTE CFSSL >:8888/api/v1/cfssl/revoke
(optionally) cfssl ocsprefresh -loglevel 0 -db-config configuration/ca/postgres.json -ca root_ca.pem -responder ocsp.pem -responder-key ocsp-key.pem
```

The common reasons of revocation can be following:

```
    unspecified (0)
    keyCompromise (1)
    cACompromise (2)
    affiliationChanged (3)
    superseded (4)
    cessationOfOperation (5)
    certificateHold (6)
    removeFromCRL (8)
    privilegeWithdrawn (9)
    aACompromise (10)
```
