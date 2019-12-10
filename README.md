# cfssl-experiments

![image](https://raw.githubusercontent.com/storojs72/cfssl-experiments/master/miscellaneous/cfssl-private-ca.png)

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
docker run --rm --name cfssl -v "$(pwd)":/cfssl --entrypoint cfssljson cfssl:experiments -f /cfssl/ca.json -bare /cfssl/ca
```
7) Run CFSSL service:
```
docker run -d --name cfssl --network host -v "$(pwd)"/cfssl-experiments/:/cfssl cfssl:experiments serve -ca /cfssl/ca.pem -ca-key /cfssl/ca-key.pem -config /cfssl/configuration/ca/ca_auth.json -address {YOUR CFSSL HOST IP} -db-config /cfssl/configuration/ca/postgres.json
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
git apply gencert_pkcs11_1.patch
git apply gencert_pkcs11_2.patch
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
