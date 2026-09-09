FROM debian:12-slim AS builder

ARG DEBIAN_FRONTEND=noninteractive

RUN apt update \
 && apt install --no-install-recommends -y \
      git gh awscli openssh-client ca-certificates jq tar xz-utils gnupg

ARG USER=runner
ARG UID=1000
ARG GID=1000
RUN groupadd -g $GID $USER \
 && useradd -m -u $UID -g $GID -s /bin/bash $USER \
 && mkdir -p /home/$USER/.ssh.d /home/$USER/.ssh \
 && chown -R $USER:$USER /home/$USER \
 && chmod 700 /home/$USER/.ssh.d /home/$USER/.ssh

COPY --chown=$USER:$USER overlay/ /

FROM scratch

COPY --from=builder / /

USER runner

ENTRYPOINT ["/Init.sh"]
