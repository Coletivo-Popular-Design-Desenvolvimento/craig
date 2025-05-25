# ======================
# Stage 1: Build stage
# ======================
FROM debian:bullseye-slim AS build

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
  ca-certificates

# Set environment variables for build
ENV CC=gcc-10
ENV CXX=g++-10
ENV NODE_OPTIONS="--max-old-space-size=4096"

# Install FDK AAC codec
RUN git clone https://github.com/mstorsjo/fdk-aac.git /tmp/fdk-aac && \
  cd /tmp/fdk-aac && autoreconf -fiv && ./configure && make && make install

# Install FDK AAC encoder CLI
RUN git clone https://github.com/nu774/fdkaac.git /tmp/fdkaac && \
  cd /tmp/fdkaac && autoreconf -i && ./configure && make && make install

# Install Node.js
RUN curl -fsSL https://deb.nodesource.com/setup_16.x | bash - && \
  apt-get install -y nodejs

WORKDIR /app

COPY . .

RUN chmod +x run.sh && ./install.sh

# ==========================
# Stage 2: Final stage
# ==========================
FROM debian:bullseye-slim

RUN echo "deb http://deb.debian.org/debian bullseye main" > /etc/apt/sources.list.d/debian.list && \
  apt-get update && apt-get install --no-install-recommends -y \
  flac \
  nodejs \
  ca-certificates && \
  rm -rf /var/lib/apt/lists/*

# Copy only what's needed from build stage
COPY --from=build /usr/local /usr/local
COPY --from=build /app /app

WORKDIR /app

ENV NODE_OPTIONS="--max-old-space-size=4096"

EXPOSE 3000

CMD ["./run.sh"]
FROM debian:bullseye-slim

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
  && cd ./fdk-aac && autoreconf -fiv && ./configure && make && sudo make install \
  # Installing FDK AAC encoder CLI \
  && git clone https://github.com/nu774/fdkaac.git ./fdkaac \
  && cd ./fdkaac && autoreconf -i && ./configure && make && make install \
  # Installing node.js
  && curl -fsSL https://deb.nodesource.com/setup_16.x | bash - \
  && apt-get install -y nodejs \
  && rm -rf /var/lib/apt/lists/* ./fdk-aac ./fdkaac

WORKDIR /app

# Add a large swap file (adjust the size as needed, for example, 8GB swap)
# RUN dd if=/dev/zero of=/swapfile bs=1M count=8192 && \
#     chmod 600 /swapfile && \
#     mkswap /swapfile && \
#     swapon /swapfile

# Set environment variables
ENV CC=gcc-10
ENV CXX=g++-10
ENV NODE_OPTIONS="--max-old-space-size=4096"

COPY . .

RUN chmod +x run.sh && ./install.sh \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

EXPOSE 3000

CMD ["./run.sh"]
