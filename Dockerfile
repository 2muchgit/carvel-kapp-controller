FROM photon:3.0

RUN tdnf install -y tar wget gzip

# adapted from golang docker image
ENV PATH /usr/local/go/bin:$PATH
ENV GOLANG_VERSION 1.13.13
ENV GO_REL_ARCH linux-amd64
ENV GO_REL_SHA 0b8573c2335bebef53e819ab8d323456dc2b94838bebdbd8cc6623bb8a6d77b7

RUN set eux; \
    wget -O go.tgz "https://golang.org/dl/go${GOLANG_VERSION}.${GO_REL_ARCH}.tar.gz" --progress=dot:giga; \
    echo "${GO_REL_SHA} go.tgz" | sha256sum -c -; \
    tar -C /usr/local -xzf go.tgz; \
    rm go.tgz; \
    go version

ENV GOPATH /go
ENV PATH $GOPATH/bin:$PATH
RUN mkdir -p "$GOPATH/src" "$GOPATH/bin" && chmod -R 777 "$GOPATH"

WORKDIR /go/src/github.com/vmware-tanzu/carvel-kapp-controller/

# carvel
RUN wget -O- https://github.com/vmware-tanzu/carvel-ytt/releases/download/v0.31.0/ytt-linux-amd64 > /usr/local/bin/ytt && \
  echo "32e7cdc38202b49fe673442bd22cb2b130e13f0f05ce724222a06522d7618395  /usr/local/bin/ytt" | sha256sum -c - && \
  chmod +x /usr/local/bin/ytt && ytt version

RUN wget -O- https://github.com/vmware-tanzu/carvel-kapp/releases/download/v0.36.0/kapp-linux-amd64 > /usr/local/bin/kapp && \
  echo "22fe308f1d9ebbb829a6ea10ca80d9468ff4b9aa911b0c33788fe67d04ccb383  /usr/local/bin/kapp" | sha256sum -c - && \
  chmod +x /usr/local/bin/kapp && kapp version

RUN wget -O- https://github.com/vmware-tanzu/carvel-kbld/releases/download/v0.28.0/kbld-linux-amd64 > /usr/local/bin/kbld && \
  echo "3174e5b42286aab4359d2bc12a85356ba520744fd4e26d6511fb8d705e7170c3  /usr/local/bin/kbld" | sha256sum -c - && \
  chmod +x /usr/local/bin/kbld && kbld version

RUN wget -O- https://github.com/vmware-tanzu/carvel-imgpkg/releases/download/v0.6.0/imgpkg-linux-amd64 > /usr/local/bin/imgpkg && \
  echo "b0d29d28a28db5632ce48cd9ea414ae1d3c9da382c96c72abb9961587ffb657f  /usr/local/bin/imgpkg" | sha256sum -c - && \
  chmod +x /usr/local/bin/imgpkg && imgpkg version

RUN wget -O- https://github.com/vmware-tanzu/carvel-vendir/releases/download/v0.19.0/vendir-linux-amd64 > /usr/local/bin/vendir && \
  echo "7f4634715be0219c779a0620f4aabd79a178a733bf29ef87428e758391aef148  /usr/local/bin/vendir" | sha256sum -c - && \
  chmod +x /usr/local/bin/vendir && vendir version


# [DEPRECATED] Helm V2
# Maintaining two versions of helm until we drop support in a future release
RUN wget -O- https://get.helm.sh/helm-v2.17.0-linux-amd64.tar.gz > /helm && \
  echo "f3bec3c7c55f6a9eb9e6586b8c503f370af92fe987fcbf741f37707606d70296  /helm" | sha256sum -c - && \
  mkdir /helm-v2-unpacked && tar -C /helm-v2-unpacked -xzvf /helm

RUN wget -O- https://get.helm.sh/helm-v3.5.3-linux-amd64.tar.gz > /helm && \
  echo "2170a1a644a9e0b863f00c17b761ce33d4323da64fc74562a3a6df2abbf6cd70  /helm" | sha256sum -c - && \
  mkdir /helm-unpacked && tar -C /helm-unpacked -xzvf /helm

# sops
RUN wget -O- https://github.com/mozilla/sops/releases/download/v3.6.1/sops-v3.6.1.linux > /usr/local/bin/sops && \
  echo "b2252aa00836c72534471e1099fa22fab2133329b62d7826b5ac49511fcc8997  /usr/local/bin/sops" | sha256sum -c - && \
  chmod +x /usr/local/bin/sops && sops -v

# kapp-controller
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -mod=vendor -ldflags=-buildid= -trimpath -o controller ./cmd/main.go

# --- run image ---
FROM photon:3.0

RUN tdnf install -y git openssh-clients shadow-tools sed

RUN groupadd -g 2000 kapp-controller && useradd -r -u 1000 --create-home -g kapp-controller kapp-controller
RUN chmod g+w /etc/pki/tls/certs/ca-bundle.crt && chgrp kapp-controller /etc/pki/tls/certs/ca-bundle.crt
USER kapp-controller

# Name it kapp-controller to identify it easier in process tree
COPY --from=0 /go/src/github.com/vmware-tanzu/carvel-kapp-controller/controller kapp-controller

# fetchers
COPY --from=0 /helm-v2-unpacked/linux-amd64/helm helmv2
COPY --from=0 /helm-unpacked/linux-amd64/helm .
COPY --from=0 /usr/local/bin/imgpkg .
COPY --from=0 /usr/local/bin/vendir .

# templaters
COPY --from=0 /usr/local/bin/ytt .
COPY --from=0 /usr/local/bin/kbld .
COPY --from=0 /usr/local/bin/sops .

# deployers
COPY --from=0 /usr/local/bin/kapp .

ENV PATH="/:${PATH}"
ENTRYPOINT ["/kapp-controller"]
