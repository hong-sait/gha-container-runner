FROM ghcr.io/actions/actions-runner:2.334.0

USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
    && install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl \
    && rm kubectl \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /runner-state /home/runner/_work \
    && chown -R runner:runner /runner-state /home/runner/_work

COPY entrypoint.sh /usr/local/bin/runner-entrypoint.sh
COPY remove-runner.sh /usr/local/bin/remove-runner.sh

ENTRYPOINT ["/usr/local/bin/runner-entrypoint.sh"]
