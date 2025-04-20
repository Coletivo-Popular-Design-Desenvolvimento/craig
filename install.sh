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
DATABASE_NAME="craig"
POSTGRESQL_USER="$(whoami)"
POSTGRESQL_PASSWORD="craig"
POSTGRESQL_START_TIMEOUT_S=10
REDIS_START_TIMEOUT_S=10
DATABASE_URL=\"postgresql://$POSTGRESQL_USER:$POSTGRESQL_PASSWORD@localhost:5432/$DATABASE_NAME?schema=public\"

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

start_redis() {
  local start_time_s
  local current_time_s

  # otherwise 'redis-server' will not be found if this function
  # is ran separately
  source ~/.nvm/nvm.sh || true
  nvm use $NODE_VERSION

  # start redis and check if it is running, timeout if it hasn't started
  info "Starting Redis server..."

  if ! redis-cli ping | grep -q "PONG"
  then
    sudo systemctl enable --now redis-server # is disabled by default

    start_time_s=$(date +%s)

    while ! redis-cli ping | grep -q "PONG"
    do
      current_time_s=$(date +%s)
      sleep 1 # otherwise we get a bunch of connection refused errors

      if [[ $current_time_s-$start_time_s -ge $REDIS_START_TIMEOUT_S ]]
      then
        error "Redis server is not running or not accepting connections"
        info "Make sure Redis was successfully installed and rerun this script"
        info "You can also try increasing the REDIS_START_TIMEOUT_S value (currently $REDIS_START_TIMEOUT_S seconds)"
        exit 1
      fi
    done 
  fi

}

start_postgresql() {
  local start_time_s
  local current_time_s

  info "Starting PostgreSQL server..."

  if ! pg_isready
  then
    sudo systemctl enable --now postgresql # is enabled by default

    start_time_s=$(date +%s)

    while ! pg_isready
    do
      current_time_s=$(date +%s)
      sleep 1 # otherwise we get a bunch of connection refused errors

      if [[ $current_time_s-$start_time_s -ge $POSTGRESQL_START_TIMEOUT_S ]]
      then
        error "PostgreSQL server is not running or not accepting connections"
        info "Make sure PostgreSQL was successfully installed and rerun this script"
        info "You can also try increasing the POSTGRESQL_START_TIMEOUT_S value (currently $POSTGRESQL_START_TIMEOUT_S seconds)"
        exit 1
      fi
    done 
  fi

  # create postgreSQL database if it doesn't already exist
  if ! sudo -u postgres -i psql -lqt | cut -d \| -f 1 | grep -qw "$DATABASE_NAME";
  then
    sudo -u postgres -i createdb "$DATABASE_NAME"
  fi

  # Check if user exists
  if ! sudo -u postgres -i psql -t -c '\du' | cut -d \| -f 1 | grep -qw "$POSTGRESQL_USER"
  then
    sudo -u postgres -i psql -c "CREATE USER $POSTGRESQL_USER WITH PASSWORD '$POSTGRESQL_PASSWORD';"
  fi

  sudo -u postgres -i psql -c "GRANT ALL PRIVILEGES ON DATABASE $DATABASE_NAME TO $POSTGRESQL_USER;"
  sudo -u postgres -i psql -c "GRANT ALL ON SCHEMA public TO $POSTGRESQL_USER;"
  sudo -u postgres -i psql -c "GRANT USAGE ON SCHEMA public TO $POSTGRESQL_USER;"
  sudo -u postgres -i psql -c "ALTER DATABASE $DATABASE_NAME OWNER TO $POSTGRESQL_USER;"
  
  sudo -u postgres -i psql -c "\l" # unnecessary but just for debugging
}

config_yarn(){
  info "Configuring yarn..."

  # install dependencies
  yarn install

  # config prisma
  #yarn prisma:generate
  #yarn prisma:deploy

  # build
  yarn run build

  # sync Discord slash commands globally
  yarn run sync

  # only sync Discord slash commands to the guild
  # specified by DEVELOPMENT_GUILD_ID in install.config
  yarn run sync:dev 
}

start_app(){
  # otherwise 'pm2' will not be found if this function
  # is ran separately
  source ~/.nvm/nvm.sh || true
  nvm use $NODE_VERSION

  info "Starting Craig..."

  cd "$craig_dir/apps/bot" && pm2 start "ecosystem.config.js"
  cd "$craig_dir/apps/dashboard" && pm2 start "ecosystem.config.js"
  cd "$craig_dir/apps/download" && pm2 start "ecosystem.config.js"
  cd "$craig_dir/apps/tasks" && pm2 start "ecosystem.config.js"

  pm2 save

  cd "$craig_dir"
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
  info "Start time: $(date +%H:%M:%S)"

  install_apt_packages
  install_node
  start_redis
  #start_postgresql
  config_yarn
  config_cook
  start_app

  info "Craig installation finished..."
  info "End time: $(date +%H:%M:%S)"
  info "Log output: $craig_dir/install.log"

} 2>&1 | tee "$craig_dir/install.log"
