FROM golang:1.13.3@sha256:6a693fbaba7dd8d816f6afce049fb92b280c588e0a677c4c8db26645e613fc15

WORKDIR /workdir
RUN git clone https://github.com/cloudflare/cfssl /workdir
RUN git checkout ebe01990a23a309186790f4f8402eec68028f148
COPY patches/ocsp_2.patch /workdir
RUN git apply ocsp_2.patch
RUN git clone https://github.com/cloudflare/cfssl_trust.git /etc/cfssl && \
    make clean && \
    make bin/rice && ./bin/rice embed-go -i=./cli/serve && \
    make all && cp bin/* /usr/bin/

# set goose for migration purpose
RUN go get bitbucket.org/liamstask/goose/cmd/goose
COPY configuration/migration/pg/dbconf.yml /workdir/certdb/pg/dbconf.yml

EXPOSE 8888

ENTRYPOINT ["cfssl"]
CMD ["--help"]
