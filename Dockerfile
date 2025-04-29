# This docker file represents a multistage docker build for the spacelift 
# runner images running our cdktf code and planing it 
ARG BASE_IMAGE=alpine:3.21
ARG NODE_VERSION=18.19.1
# hadolint ignore=DL3006
# alias the base image as common 
FROM ${BASE_IMAGE} AS common 

SHELL ["/bin/ash", "-eo", "pipefail", "-c"]

# hadolint ignore=DL3018
RUN apk --no-cache add \
    ca-certificates \
    curl

FROM common AS base
# This basially ceates the base image it has the tools that needed 
# so that the runner can do the needed terraform command 

ARG TARGETARCH
# use the ash shell of the alpin image and a special pipe to handle how to report commands that failed (we should know more what this does)
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]

# some spacelift specific command not of interest, i think that is related to the different runners and the DNS names and how to resolve that 
RUN echo "hosts: files dns" > /etc/nsswitch.conf \
    && adduser --disabled-password --uid=1983 spacelift

# hadolint ignore=DL3018
RUN apk -U upgrade && apk add --no-cache \
    build-base \
    gcc \
    musl-dev \
    libffi-dev \
    git \
    jq \
    xz \
    openssh \
    openssh-keygen \
    tzdata \
    bash \
    npm \
    yarn \
    python3

# This command checks if the python env var is configured and if not it configures it via the ln(link) command
RUN [ -e /usr/bin/python ] || ln -s python3 /usr/bin/python

# Install latest NPM version, cdktf and prettier
# Note: Remove later or install with bun (also rm npm & yarn)
RUN npm install -g npm@latest && \
    yarn global add cdktf-cli@latest prettier@latest

# Download infracost
ADD "https://github.com/infracost/infracost/releases/latest/download/infracost-linux-${TARGETARCH}.tar.gz" /tmp/infracost.tar.gz
RUN tar -xzf /tmp/infracost.tar.gz -C /bin && \
    mv "/bin/infracost-linux-${TARGETARCH}" /usr/local/bin/infracost && \
    chmod 755 /usr/local/bin/infracost && \
    rm /tmp/infracost.tar.gz

# Install regula
RUN REGULA_LATEST_VERSION=$(curl -s https://api.github.com/repos/fugue/regula/releases/latest | grep "tag_name" | cut -d'v' -f2 | cut -d'"' -f1) && \
    curl -L "https://github.com/fugue/regula/releases/download/v${REGULA_LATEST_VERSION}/regula_${REGULA_LATEST_VERSION}_Linux_x86_64.tar.gz" --output /tmp/regula.tar.gz && \
    tar -xzf /tmp/regula.tar.gz -C /bin && \
    mv "/bin/regula" /usr/local/bin/regula && \
    chmod 755 /usr/local/bin/regula && \
    rm /tmp/regula.tar.gz

# This stage basically downloads and extracts Bun for the runner to use with out terraform command 

FROM oven/bun:alpine AS bun

# This stage festch the aws cli related tools and packages to be used when communicating with AWS to create resources

FROM node:${NODE_VERSION}-alpine AS node


# hadolint ignore=DL3007
FROM ghcr.io/spacelift-io/aws-cli-alpine:latest AS aws-cli

# back to the base image where 
# - copy the aws CLI related binaies
# - copy the bun related binaries

# we should add a terraform binary stage here where we get the latest terraform versions 
# hadolint ignore=DL3007
FROM hashicorp/terraform:1.11 AS terraform-latest

FROM base

# Copy AWS CLI binaries (from ghcr.io/spacelift-io/aws-cli-alpine)
COPY --from=aws-cli /usr/local/aws-cli/ /usr/local/aws-cli/
COPY --from=aws-cli /aws-cli-bin/ /usr/local/bin/

# Copy node JS ver 
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/bin/npm /usr/local/bin/npm
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules

# Copy the latest terraform version into the base layer
COPY --from=terraform-latest /bin/terraform /usr/local/bin/

# Copy Bun binary
COPY --from=bun /usr/local/bin/bun /usr/local/bin/

# This kinda links the bunx command o bun 
RUN ln -s /usr/local/bin/bun /usr/local/bin/bunx

# Check versions
RUN echo "Software installed:"; \
    aws --version; \
    echo "CDKTF v$(cdktf --version)"; \
    infracost --version; \
    echo "Prettier v$(prettier --version)"; \
    echo "Regula $(regula version)"; \
    echo "Bun v$(bun --version)"; \
    terraform --version; \
    node -v;

USER spacelift
