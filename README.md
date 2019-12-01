# cfssl-experiments

![image](https://github.com/cossacklabs/acra-engineering-demo/blob/storojs72/T1230_do_blogpost/do-blogpost/version1/screenshots/11.png)

This is a variant of CFSSL remote service deployment with a single Dockerfile.
No need to install golang or deal with cfssl source code.
Tested on Digital Ocean droplet with Ubuntu 18.04 LTS operating system.


##### On remote host for CFSSL

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
6) Generace self-signed certificate for CFSSL service:
```
docker run --rm --name cfssl -v "$(pwd)":/cfssl cfssl:experiments gencert -loglevel=2 -initca /cfssl/configuration/ca/ca_subj.json > ca.json
docker run --rm --name cfssl -v "$(pwd)":/cfssl --entrypoint cfssljson cfssl:experiments -f /cfssl/ca.json -bare /cfssl/ca
```
7) Run CFSSL service:
```
docker run -d --name cfssl --network host -v "$(pwd)"/cfssl-experiments/:/cfssl cfssl:experiments serve -ca /cfssl/ca.pem -ca-key /cfssl/ca-key.pem -config /cfssl/configuration/ca/ca_auth.json -address {YOUR CFSSL HOST IP} -db-config /cfssl/configuration/ca/postgres.json
```
