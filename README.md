# cfssl-experiments

![image](https://raw.githubusercontent.com/storojs72/cfssl-experiments/master/screenshots/cfssl-private-ca.png)

This is a variant of CFSSL remote service deployment with a single Dockerfile.
CFSSL is deployed with a local PostgreSQL database for storing issued certificates.
With a help of CFSSL's API (auth-sign endpoint) it is possible to organize mutually 
authenticated and encrypted communications between services.   

No need to install golang or deal with cfssl source code.
Tested on Digital Ocean droplet with Ubuntu 18.04 LTS operating system with 
two go applications (simple server and client) from cfssl github repository (https://github.com/cloudflare/cfssl/tree/master/transport/example) 


##### On remote host for Intermediate CA

1) Install docker (if not installed):
```
apt update
apt install docker.io
systemctl start docker
systemctl enable docker
```
2) Clone this repository:
```
git clone https://github.com/storojs72/cfssl-experiments
cd cfssl-experiments
```
3) Set postgres database container for accounting issued certificates:
```
docker pull postgres:latest
docker run -p 5432:5432 -e POSTGRES_USER=cfssl -e POSTGRES_PASSWORD=cfssl --name postgres -d postgres:latest
```
4) Build CFSSL image:
```
docker build -t cfssl:experiments .
```
5) Migrate CFSSL database to postgres container:
```
docker run --rm --network host --entrypoint goose cfssl:experiments -path certdb/pg/ -env cfssl-experiments up
```
6) Generate self-signed certificate for CFSSL service:
```
docker run --rm --name cfssl -v "$(pwd)":/cfssl cfssl:experiments gencert -loglevel=2 -initca /cfssl/configuration/ca/ca_subj.json > ca.json
docker run --rm -v "$(pwd)":/cfssl --entrypoint cfssljson cfssl:experiments -f /cfssl/ca.json -bare /cfssl/ca
```


##### OCSP service

7) Generate certificate for OCSP service:
```
docker run --rm -v "$(pwd)":/cfssl cfssl:experiments gencert -loglevel=2 -ca /cfssl/ca.pem -ca-key /cfssl/ca-key.pem /cfssl/configuration/ocsp/ocsp_subj.json > ocsp.json
docker run --rm -v "$(pwd)":/cfssl --entrypoint cfssljson cfssl:experiments -f /cfssl/ocsp.json -bare /cfssl/ocsp
```

8) Run CFSSL service:
```
docker run -d --name cfssl --network host -v "$(pwd)":/cfssl cfssl:experiments serve -loglevel=0 -ca /cfssl/ca.pem -ca-key /cfssl/ca-key.pem -config /cfssl/configuration/ca/ca_auth.json -address 142.93.46.4 -db-config /cfssl/configuration/migration/postgres.json -responder /cfssl/ocsp.pem -responder-key /cfssl/ocsp-key.pem
```

9) Run OCSP service:
```
docker run -d --name ocsp --network host -v "$(pwd)":/cfssl cfssl:experiments ocspserve -loglevel=0 -address 142.93.46.4 -port 8889 -db-config /cfssl/configuration/migration/postgres.json
```

10) Test connection from toy server:
```
go run transport/example/maserver/server.go -f transport/example/maserver/server_auth_config.json
```

11) Refresh ocsp responces:
```
docker run --rm --network host -v "$(pwd)":/cfssl cfssl:experiments ocsprefresh -loglevel=0 -db-config /cfssl/configuration/migration/postgres.json -ca /cfssl/ca.pem -responder /cfssl/ocsp.pem -responder-key /cfssl/ocsp-key.pem
```

BONUS - add to crontab:
```
crontab -e
* * * * *  docker run --rm --network host -v /root/cfssl-experiments:/cfssl cfssl:experiments ocsprefresh -loglevel=0 -db-config /cfssl/configuration/migration/postgres.json -ca /cfssl/ca.pem -responder /cfssl/ocsp.pem -responder-key /cfssl/ocsp-key.pem
```

12) Test connection from a toy client:
```
go run transport/example/maclient/client.go -f transport/example/maclient/client_auth_config.json
```

Set of steps to revoke certificate:

- get serial number and authority_key_id of the certificate (if you have access to .pem):
```
cfssl certinfo -cert transport/example/maserver/creds/automatic/server.pem
```
- perform revocation:
```
curl -d '{"serial": "643283264116739598736176251779770164305825300516 < in decimal!!! >","authority_key_id":"2edbc16d39d1d7d07262f1e18dd16bea29310340 < in hex!!! >","reason":"superseded"}' <address of your remote CFSSL>:8888/api/v1/cfssl/revoke
```
- refresh ocsp table:
```
cfssl ocsprefresh -loglevel 0 -db-config configuration/ca/postgres.json -ca root_ca.pem -responder ocsp.pem -responder-key ocsp-key.pem
```

Reasons of revocations:

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


##### On own laptop for hardware-baked Root CA

This is an example of building Root CA with strengthen security on your laptop. It was tested with SafeNet 5110 tokens.
It is assumed that you have your token installed (a PKCS#11 vendor library is presented: `libeTPkcs11.so` - for SafeNet 5110. Other vendors provide own libraries as PKCS#11 implementations)
and token is initialized (SO/User pin are set)

1) Clone original CFSSL repository:

```
git clone https://github.com/cloudflare/cfssl && cd cfssl
git checkout ebe01990a23a309186790f4f8402eec68028f148
```

2) Apply patches that add ability to CFSSL to work with PKCS#11 tokens (tamper-resistant hardware key storages) and refresh dependencies:

```
git apply patches/gencert_pkcs11_1.patch
git apply patches/gencert_pkcs11_2.patch
go mod tidy
go mod vendor
```

3) Install cfssl as usually:

```
make
make install
```

4) Initialize your Root CA:

```
cfssl gencert -pkcs11-module <PATH TO libeTPkcs11.so> -pkcs11-token <LABEL OF TOKEN> -pkcs11-pin <TOKEN USER PIN> -loglevel=0 -initca <CFSSL JSON SUBJECT OF ROOT CA>
```

The result should be similar to:

```
2019/12/10 15:00:44 [INFO] generating a new CA key and certificate from CSR
2019/12/10 15:00:44 [INFO] use pkcs11 token: cfssl
2019/12/10 15:00:45 [DEBUG] Loading PKCS11 Module /usr/lib/libeTPkcs11.so
2019/12/10 15:00:45 [INFO] encoded CSR
2019/12/10 15:00:45 [DEBUG] validating configuration
2019/12/10 15:00:45 [DEBUG] validate local profile
2019/12/10 15:00:45 [DEBUG] profile is valid
2019/12/10 15:00:45 [INFO] signed certificate with serial number 465284377044240070058142226389047897191304820238
{"cert":"-----BEGIN CERTIFICATE-----\nMIICqTCCAhKgAwIBAgIUUYASs9p6S651wOTV+zWcMyOqdg4wDQYJKoZIhvcNAQEF\nBQAwbzELMAkGA1UEBhMCVUExDTALBgNVBAgTBEtpZXYxDTALBgNVBAcTBEtpZXYx\nFDASBgNVBAoTC0Nvc3NhY2tMYWJzMRowGAYDVQQLExFDRlNTTCBleHBlcmltZW50\nczEQMA4GA1UEAxMHUm9vdCBDQTAeFw0xOTEyMTAxMjU2MDBaFw0yNDEyMDgxMjU2\nMDBaMG8xCzAJBgNVBAYTAlVBMQ0wCwYDVQQIEwRLaWV2MQ0wCwYDVQQHEwRLaWV2\nMRQwEgYDVQQKEwtDb3NzYWNrTGFiczEaMBgGA1UECxMRQ0ZTU0wgZXhwZXJpbWVu\ndHMxEDAOBgNVBAMTB1Jvb3QgQ0EwgZ8wDQYJKoZIhvcNAQEBBQADgY0AMIGJAoGB\nALAIL8Lm/MXI3ByKjy2sUBz0mvODGtoUKycvAkOez0+mwq0icw6TAPck2yctnKFa\n4ldesWolgYEo+5Y1M2XhpU8LCVW+AA/gCrPyBQ71r2K25H1FUcWDccHfy9N00AL8\n1Reu8BqCg0xGAQk3nFNsuyiRFK1d89TlP2YVnw0J86cPAgMBAAGjQjBAMA4GA1Ud\nDwEB/wQEAwIBBjAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBRpL2d6r25Tau3U\nS9xsleO8zV+x0jANBgkqhkiG9w0BAQUFAAOBgQCI/jkxVdccfyxnMTimm0SUIYSA\n0LVvjobzjf7AL+/dOjtktUvp86yJDIQzhjlS1bcSBfqrH1YBImBwczEjYMN0SYhJ\nSmtjWH6Z6qNnz0XXTQDUAzX/CgXOXxrofBA3L4VF3/aVTbY5u1haZSyOsUcA8XNI\n8sHO/GiKDcYITHaGPQ==\n-----END CERTIFICATE-----\n","csr":"-----BEGIN CERTIFICATE REQUEST-----\nMIIBrzCCARgCAQAwbzELMAkGA1UEBhMCVUExDTALBgNVBAgTBEtpZXYxDTALBgNV\nBAcTBEtpZXYxFDASBgNVBAoTC0Nvc3NhY2tMYWJzMRowGAYDVQQLExFDRlNTTCBl\neHBlcmltZW50czEQMA4GA1UEAxMHUm9vdCBDQTCBnzANBgkqhkiG9w0BAQEFAAOB\njQAwgYkCgYEAsAgvwub8xcjcHIqPLaxQHPSa84Ma2hQrJy8CQ57PT6bCrSJzDpMA\n9yTbJy2coVriV16xaiWBgSj7ljUzZeGlTwsJVb4AD+AKs/IFDvWvYrbkfUVRxYNx\nwd/L03TQAvzVF67wGoKDTEYBCTecU2y7KJEUrV3z1OU/ZhWfDQnzpw8CAwEAAaAA\nMA0GCSqGSIb3DQEBBQUAA4GBAGeR59vwKZOeccgxQCG0KKjAHwjLUjapnWgSDtmU\nk2NaQi6IqxJQKzT1USzoQJ2mBKaECfIWZKgFLD4QJj87r0qghQZY1eYU/1Od9cWg\nDBGqUuAUnFxb+aJeN/qobWjMsLD32ojeDfdOg+P3sgERnKuKCXKR3e83DIFep136\nubRh\n-----END CERTIFICATE REQUEST-----\n","key":"hardware-baked private key"}
```

Additional resources:

1) OpenSC and pkcs11-tool (https://github.com/OpenSC/OpenSC)
2) CFSSL community discussion on PKCS#11 (1) (https://github.com/cloudflare/cfssl/issues/563)
3) CFSSL community discussion on PKCS#11 (2) (https://github.com/cloudflare/cfssl/issues/247)


#### Link certificate authorities
Combine CA certificates from Root CA and Intermediate CA:
```
cat configuration/root-ca/root-ca.pem configuration/intermediate-ca/intermediate.pem > configuration/chainCA.pem
```

Verify certificate signature:
```
openssl verify -CAfile configuration/intermediate-ca/intermediate.pem configuration/server.pem
```






Backround:

PKI

TLS

OCSP

CFSSL

PKCS#11

Bob's (security engineer) work:

1) Installing CFSSL locally (for RootCA):
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

2) Create RootCA:
```
[on Bob's local computer]

cfssl gencert -pkcs11-module /usr/lib/libeTPkcs11.so -pkcs11-token cfssl -pkcs11-pin 'trian0n' -loglevel=0 -initca configuration/root-ca/root-ca-subj.json | cfssljson -bare root
```

3) Prerequisites for remote CFSSL service (for IntermediateCA):
```
[on remote host for IntermediateCA]

apt update
apt install docker.io
systemctl start docker
systemctl enable docker

git clone https://github.com/storojs72/cfssl-experiments && cd cfssl-experiments

docker pull postgres:latest
docker run -p 5432:5432 -e POSTGRES_USER=cfssl -e POSTGRES_PASSWORD=cfssl --name postgres -d postgres:latest

docker build -t cfssl:experiments .
docker run --rm --network host --entrypoint goose cfssl:experiments -path certdb/pg/ -env cfssl-experiments up
```

4) Create IntermediateCA:
```
[on remote host for IntermediateCA]

docker run --rm --name cfssl -v "$(pwd)":/cfssl cfssl:experiments genkey -loglevel=2 /cfssl/configuration/intermediate-ca/intermediate_ca_subj.json > intermediate.json
docker run --rm -v "$(pwd)":/cfssl --entrypoint cfssljson cfssl:experiments -f /cfssl/ca.json -bare /cfssl/ca

[on Bob's local computer]

scp root@142.93.46.4:/root/cfssl-experiments/intermediate.csr intermediate.csr
cfssl sign -pkcs11-module /usr/lib/libeTPkcs11.so -pkcs11-token cfssl -pkcs11-pin 'trian0n' -ca root.pem -csr intermediate.csr -loglevel=0 -config configuration/root-ca/root_ca_config.json -profile intermediate configuration/intermediate-ca/intermediate_ca_subj.json | cfssljson -bare intermediate
scp intermediate.pem root@142.93.46.4:/root/cfssl-experiments/intermediate.pem
```

5) Create OCSP service:
```
[on remote host for IntermediateCA]

docker run --rm -v "$(pwd)":/cfssl cfssl:experiments gencert -loglevel=2 -ca /cfssl/intermediate.pem -ca-key /cfssl/intermediate-key.pem /cfssl/configuration/ocsp/ocsp_subj.json > ocsp.json
docker run --rm -v "$(pwd)":/cfssl --entrypoint cfssljson cfssl:experiments -f /cfssl/ocsp.json -bare /cfssl/ocsp
```

6) Run IntermediateCA service:
```
[on remote host for IntermediateCA]

docker run -d --name cfssl --network host -v "$(pwd)":/cfssl cfssl:experiments serve -loglevel=0 -ca /cfssl/intermediate.pem -ca-key /cfssl/intermediate-key.pem -config /cfssl/configuration/intermediate-ca/intermediate_ca_config.json -address 142.93.46.4 -db-config /cfssl/configuration/migration/postgres.json -responder /cfssl/ocsp.pem -responder-key /cfssl/ocsp-key.pem
```

7) Run OCSP service:
```
[on remote host for IntermediateCA]

docker run -d --name ocsp --network host -v "$(pwd)":/cfssl cfssl:experiments ocspserve -loglevel=0 -address 142.93.46.4 -port 8889 -db-config /cfssl/configuration/migration/postgres.json
```

8) Set OCSP responces autoupdate:

```
[on remote host for IntermediateCA]

crontab -e
* * * * *  docker run --rm --network host -v /root/cfssl-experiments:/cfssl cfssl:experiments ocsprefresh -loglevel=0 -db-config /cfssl/configuration/migration/postgres.json -ca /cfssl/intermediate.pem -responder /cfssl/ocsp.pem -responder-key /cfssl/ocsp-key.pem
```

8) Be ready to provide trusted chain of certificates:
```
[on Bob's local computer]

cat root.pem intermediate.pem > chainCA.pem
```


Alice's (software engineer) work:

1) Create application (client and server) that should have mutually-authenticated and encrypted communication. 
For this purpose we will use toy example (written on Go) of client and server provided with CFSSL
```
git clone https://github.com/storojs72/cfssl-experiments && cd cfssl-experiments
git clone https://github.com/cloudflare/cfssl & cd cfssl
git checkout ebe01990a23a309186790f4f8402eec68028f148
git apply ../patches/revoke_ocsp.patch
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

Bob is able to revoke certificates. This is a set of steps to do it:

- get serial number and authority_key_id of the certificate (if you have access to .pem. Alternatively, it can be retrieved from the database):
```
cfssl certinfo -cert server.pem
```
- perform revocation:
```
curl -d '{"serial": "643283264116739598736176251779770164305825300516 < in decimal!!! >","authority_key_id":"2edbc16d39d1d7d07262f1e18dd16bea29310340 < in hex!!! >","reason":"superseded"}' <address of your remote CFSSL>:8888/api/v1/cfssl/revoke
```
- refresh ocsp table:
```
cfssl ocsprefresh -loglevel 0 -db-config configuration/ca/postgres.json -ca root_ca.pem -responder ocsp.pem -responder-key ocsp-key.pem
```

Reasons of revocation:

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