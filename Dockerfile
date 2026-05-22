FROM ghcr.io/actions/actions-runner:2.334.0

USER root
RUN mkdir -p /runner-state /home/runner/_work \
    && chown -R runner:runner /runner-state /home/runner/_work

COPY entrypoint.sh /usr/local/bin/runner-entrypoint.sh
COPY remove-runner.sh /usr/local/bin/remove-runner.sh

ENTRYPOINT ["/usr/local/bin/runner-entrypoint.sh"]
