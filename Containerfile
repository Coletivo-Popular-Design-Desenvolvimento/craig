FROM debian:bullseye-slim AS base

ENV NODE_VERSION=18.18.2

RUN echo "deb http://deb.debian.org/debian bullseye main" > /etc/apt/sources.list.d/debian.list

RUN apt-get update && \
  apt-get install --no-install-recommends -y \
  gcc-10 \
  g++-10 \
  python3-setuptools \
  sudo \
  flac \
  curl \
  git \
  build-essential \
  autoconf \
  automake \
  libtool \
  pkg-config \
  gawk \
  wget \
  ca-certificates \
  # Installing FDK AAC codec library \
  && git clone https://github.com/mstorsjo/fdk-aac.git ./fdk-aac \
  && cd ./fdk-aac && autoreconf -fiv && ./configure && make && make install \
  # Installing FDK AAC encoder CLI \
  && git clone https://github.com/nu774/fdkaac.git ./fdkaac \
  && cd ./fdkaac && autoreconf -i && ./configure && make && make install \
  # Installing node.js
  && curl -fsSL https://deb.nodesource.com/setup_16.x | bash -

RUN apt-get install -y nodejs --no-install-recommends\
  && rm -rf /var/lib/apt/lists/* ./fdk-aac ./fdkaac

WORKDIR /app

# Add a large swap file (adjust the size as needed, for example, 8GB swap)
# RUN dd if=/dev/zero of=/swapfile bs=1M count=8192 && \
#     chmod 600 /swapfile && \
#     mkswap /swapfile && \
#     swapon /swapfile

# install.sh is split into --step phases so each part lands in its own Docker
# layer, ordered from least to most frequently changed. Only the parts whose
# inputs actually changed are rebuilt; the rest come from cache.

# Copy only the installer for the system-level layers (no source dependency)
COPY install.sh ./
RUN chmod +x install.sh

# Layer 1 - system packages (rarely changes)
ENV CC=gcc-10
ENV CXX=g++-10
RUN ./install.sh --step apt && apt-get clean && rm -rf /var/lib/apt/lists/*

# Layer 2 - node/nvm/yarn/pm2 toolchain (rarely changes)
RUN ./install.sh --step node

# Layer 3 - JS dependencies: only rebuilds when a manifest/lockfile changes.
# All workspace package.json files must be present for yarn workspaces to resolve.
ENV NODE_OPTIONS="--max-old-space-size=4096"
COPY package.json yarn.lock ./
COPY apps/bot/package.json       apps/bot/
COPY apps/dashboard/package.json apps/dashboard/
COPY apps/download/package.json  apps/download/
COPY apps/tasks/package.json     apps/tasks/
# The @prisma/client postinstall generates the typed client (Guild, etc.) that
# the TypeScript build needs, and it must find the schema at install time.
COPY prisma ./prisma
RUN ./install.sh --step deps

# Build-time secrets live here, after yarn install, so changing a token does
# not invalidate the (slow) dependency layer above.
ARG CLIENT_ID
ARG CLIENT_SECRET
ARG DISCORD_BOT_TOKEN
ARG DISCORD_APP_ID
ARG DEVELOPMENT_GUILD_ID
ENV CLIENT_ID=${CLIENT_ID}
ENV CLIENT_SECRET=${CLIENT_SECRET}
ENV DISCORD_BOT_TOKEN=${DISCORD_BOT_TOKEN}
ENV DISCORD_APP_ID=${DISCORD_APP_ID}
ENV DEVELOPMENT_GUILD_ID=${DEVELOPMENT_GUILD_ID}

# Layer 4 - full source + build (rebuilds on source change, deps stay cached)
COPY . .
RUN ./install.sh --step build
RUN ./install.sh --step cook

RUN chmod +x run.sh

EXPOSE 3000 5029

CMD ["./run.sh"]
