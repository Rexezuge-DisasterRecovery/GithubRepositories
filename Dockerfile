FROM debian:12-slim AS builder

ARG DEBIAN_FRONTEND=noninteractive

RUN apt update \
 && apt install --no-install-recommends -y \
      git gh awscli openssh-client ca-certificates jq tar xz-utils gnupg

COPY overlay/ /

FROM scratch

COPY --from=builder / /

ENTRYPOINT ["/Init.sh"]
