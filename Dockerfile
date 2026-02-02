FROM debian:12-slim

ARG DEBIAN_FRONTEND=noninteractive

RUN apt update \
 && apt install --no-install-recommends -y \
      git gh awscli openssh-client ca-certificates jq tar xz-utils

COPY overlay/ /

ENTRYPOINT ["/app/Init.sh"]
