#!/bin/bash

set -e

craig_dir=$(dirname "$(realpath "$0")")
NODE_VERSION="18.18.2"
DATABASE_NAME="craig"
POSTGRESQL_USER="$(whoami)"
POSTGRESQL_PASSWORD="craig"
POSTGRESQL_START_TIMEOUT_S=10
REDIS_START_TIMEOUT_S=10
DATABASE_URL=\"postgresql://$POSTGRESQL_USER:$POSTGRESQL_PASSWORD@localhost:5432/$DATABASE_NAME?schema=public\"

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

{ 
  if ! sudo -v; then
    error "Sudo password entry was cancelled or incorrect."
    exit 1 
  fi

  # source "$craig_dir/install.config"

  OS="$(uname)"
  if [[ "${OS}" != "Linux" ]]
  then
    exit 1
  fi

  info "Now satarting Craig..."

  start_redis
  start_postgresql
  start_app

} 2>&1 | tee "$craig_dir/install.log"