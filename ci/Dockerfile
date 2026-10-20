# Tools image for the Jenkins pipeline (see Jenkinsfile): everything
# scripts/deploy.sh needs except the docker binary, which is mounted from the
# host together with its socket.
FROM debian:12-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl gettext-base git openssl \
 && curl -sL https://aka.ms/InstallAzureCLIDeb | bash \
 && az aks install-cli --install-location /usr/local/bin/kubectl \
      --kubelogin-install-location /usr/local/bin/kubelogin \
 && rm -rf /var/lib/apt/lists/*
