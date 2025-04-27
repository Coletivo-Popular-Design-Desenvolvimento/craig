#!/bin/bash

set -e

###################################################
# Variable definitions
###################################################

APT_DEPENDENCIES=(
  make              # cook
  inkscape          # cook
  ffmpeg            # cook
  flac              # cook
  fdkaac            # cook
  vorbis-tools      # cook
  opus-tools        # cook
  zip               # cook
  unzip             # cook
  lsb-release       # redis
  curl              # redis
  gpg               # redis
  postgresql        # web
  dbus-x11          # install
  sed               # install
  coreutils         # install
  build-essential   # install
  python3-setuptools # install
)

craig_dir=$(dirname "$(realpath "$0")")
NODE_VERSION="18.18.2"

###################################################
# Function definitions
###################################################

warning() {
    echo "[Craig][Warning]: $1"
}

error() {
    echo "[Craig][Error]: $1" >&2
}

info() {
    echo "[Craig][Info]: $1"
}

install_apt_packages() {
  info "Updating and upgrading apt packages..."
  sudo apt-get update
  sudo apt-get -y upgrade

  info "Installing apt dependencies..."
  for package in "${APT_DEPENDENCIES[@]}"
  do
    sudo apt-get -y install "$package"
  done

  # Add redis repository to apt index and install it
  # for more info, see: https://redis.io/docs/install/install-redis/install-redis-on-linux/
  curl -fsSL https://packages.redis.io/gpg | sudo gpg --yes --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/redis.list
  sudo apt-get update || true
  sudo apt-get -y install redis
}

install_node() {
  # Install and run node (must come before npm install because npm is included with node)
  # we have to source nvm first otherwise in this non-interactive script it will not be available
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
  
  # There is a version error raised somewhere in "nvm.sh"
  # because of set -e at the top of this script, we need to add the || true
  source ~/.nvm/nvm.sh || true

  nvm install $NODE_VERSION
  nvm use $NODE_VERSION

  # Install yarn globally to avoid creating package-lock.json file
  npm install -g yarn
  npm install -g pm2
}

config_yarn(){
  info "Configuring yarn..."

  # install dependencies
  yarn install

  # config prisma
  yarn prisma:generate
  yarn prisma:deploy

  # build
  yarn run build

  # sync Discord slash commands globally
  #yarn run sync

  # only sync Discord slash commands to the guild
  # specified by DEVELOPMENT_GUILD_ID in install.config
  yarn run sync:dev 
}

config_cook(){
  info "Building cook..."
  mkdir -p "$craig_dir/rec"
  "$craig_dir/scripts/buildCook.sh"
  "$craig_dir/scripts/downloadCookBuilds.sh"
}


###################################################
# Main script commands
###################################################

{ 
  info "This script requires sudo privileges to run"
  if ! sudo -v; then
    error "Sudo password entry was cancelled or incorrect."
    exit 1 
  fi

  # source "$craig_dir/install.config"

  OS="$(uname)"
  if [[ "${OS}" != "Linux" ]]
  then
    error "Craig is only supported on Linux."
    exit 1
  fi

  info "Now installing Craig..."

  install_apt_packages
  install_node
  config_yarn
  config_cook
  apt-get clean
  info "Craig installation finished..."

} 2>&1 | tee "$craig_dir/install.log"
