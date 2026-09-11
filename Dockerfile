ARG GIT_SHA=unknown
FROM debian:12-slim AS builder

ARG GIT_SHA=unknown
ARG DEBIAN_FRONTEND=noninteractive

RUN apt update \
 && apt install --no-install-recommends -y \
      git gh awscli openssh-client ca-certificates jq tar xz-utils gnupg

COPY overlay/ /

RUN echo -n "$GIT_SHA" > /GIT_SHA

FROM scratch

ARG GIT_SHA=unknown
ENV GIT_SHA=${GIT_SHA}
LABEL org.opencontainers.image.revision=${GIT_SHA}

COPY --from=builder / /

ENTRYPOINT ["/Init.sh"]
