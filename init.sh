#!/bin/bash

CLEAR_COLORS="\\e[0m"
COLOR_BG_YELLOW="\e[30;43m"
COLOR_BG_RED="\e[30;41m"
COLOR_BG_GREEN="\e[30;42m"
COLOR_BG_BLUE="\e[30;44m"

function warning() {
  echo -e "$COLOR_BG_YELLOW Warning: $1 $CLEAR_COLORS"
}
function error() {
  echo -e "$COLOR_BG_RED Error: $1 $CLEAR_COLORS"
}
function success() {
  echo -e "$COLOR_BG_GREEN OK: $1 $CLEAR_COLORS"
}
function info() {
  echo -e "$COLOR_BG_BLUE $1 $CLEAR_COLORS"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --path=*)
      WEBSERVER_PATH="${1#*=}"
      ;;
    *)
      error "Invalid argument $1"
      exit 1
  esac
  shift
done

if [ "$WEBSERVER_PATH" == "" ] ; then
  error "\"--path\" argument is not provided."
  exit 1
fi

if [ -d "$WEBSERVER_PATH" ] && [ "$(ls -A $WEBSERVER_PATH)" ]; then
  error "Directory '$WEBSERVER_PATH' already exists and it's not empty."
  exit 1
fi

# Set MySQL Root password
echo 'Enter MySql root password:'
read -r MYSQL_ROOT_PASSWORD

# Set MySQL User
echo 'Enter MySql new username:'
read -r MYSQL_USERNAME
echo "Enter password for \"$MYSQL_USERNAME\":"
read -r MYSQL_USERNAME_PASSWORD


# Set Nginx virtual hosts
WEBSERVER_HOSTS=''
while true; do
  if [ "$WEBSERVER_HOSTS" == "" ]; then
    echo "Enter hostname:"
  else
    echo "Enter one more hostname or enter \"N\":"
  fi

  read -r NEW_HOST

  if [ "$WEBSERVER_HOSTS" != "" ] && [ "$NEW_HOST" == "N" ]; then
    break
  fi
  if [ "$WEBSERVER_HOSTS" == "" ]; then
    WEBSERVER_HOSTS="$NEW_HOST"
  else
    WEBSERVER_HOSTS="$WEBSERVER_HOSTS,$NEW_HOST"
  fi
done

# Create directory structure
mkdir -p "$WEBSERVER_PATH/data/env_files"
mkdir -p "$WEBSERVER_PATH/data/nginx/config"
mkdir -p "$WEBSERVER_PATH/data/nginx/log"
mkdir -p "$WEBSERVER_PATH/data/mysql/data"
mkdir -p "$WEBSERVER_PATH/data/mysql/config"
mkdir -p "$WEBSERVER_PATH/data/composer-cache"
mkdir -p "$WEBSERVER_PATH/data/www"

# Create env files
echo "MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD" > "$WEBSERVER_PATH/data/env_files/mysql.env"
echo "VIRTUAL_HOST=$WEBSERVER_HOSTS" > "$WEBSERVER_PATH/data/env_files/nginx.env"

# Config files
cp ./MySQL/my.cnf "$WEBSERVER_PATH/data/mysql/config/my.cnf"
cp ./Nginx/basic-config.nginx "$WEBSERVER_PATH/data/nginx/config/basic-config.nginx"

IFS=',' read -r -a HOSTS_ARRAY <<< "$WEBSERVER_HOSTS"
for HOST in "${HOSTS_ARRAY[@]}"
do
  sed "s/your-site.com/$HOST/g" ./Nginx/default.conf > "$WEBSERVER_PATH/data/nginx/config/$HOST.conf"
  mkdir -p "$WEBSERVER_PATH/www/$HOST"
  printf "<?php\nphpinfo();" > "$WEBSERVER_PATH/www/$HOST/index.php"
done

# Build/pull docker images
docker build ./PHP/7.3 -t php-fpm:7.3
docker pull nginx:1.17
docker pull mysql:8.0
docker pull jwilder/nginx-proxy

# Remove old containers if exists
docker rm -f webserver-nginx-proxy webserver-nginx webserver-php-7.3 webserver-mysql

# Create network
docker network create webserver-network

# Create containers
docker run -d \
    -p 8080:80 \
    -v /var/run/docker.sock:/tmp/docker.sock:ro \
    --name webserver-nginx-proxy \
    --net webserver-network \
    jwilder/nginx-proxy

docker run -d \
    -v "$WEBSERVER_PATH/data/mysql/data:/var/lib/mysql:delegated" \
    -v "$WEBSERVER_PATH/data/mysql/config:/etc/mysql/conf.d:ro" \
    --name webserver-mysql \
    --net webserver-network \
    --env-file "$WEBSERVER_PATH/data/env_files/mysql.env" \
    mysql:8.0 \
    --default-authentication-plugin=mysql_native_password

docker run -d \
    -v "$WEBSERVER_PATH/www:/var/www:cached" \
    -v "$WEBSERVER_PATH/data/composer-cache:/home/php-user/composer-cache:delegated" \
    --name webserver-php-7.3 \
    --net webserver-network \
    php-fpm:7.3

docker run -d \
    -v "$WEBSERVER_PATH/www:/var/www:cached" \
    -v "$WEBSERVER_PATH/data/nginx/config:/etc/nginx/conf.d:ro" \
    -v "$WEBSERVER_PATH/data/nginx/log:/var/log/nginx:delegated" \
    --name webserver-nginx \
    --net webserver-network \
    --env-file "$WEBSERVER_PATH/data/env_files/nginx.env" \
    nginx:1.17

while ! docker exec -t webserver-mysql mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "select 1"; do
    echo "Wait for MySQL server 5 seconds..."
    sleep 5
done

# Create MySql user
docker exec -t webserver-mysql mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "CREATE USER '$MYSQL_USERNAME'@'%' IDENTIFIED BY '$MYSQL_USERNAME_PASSWORD';"

# Create MySQL databases for each host
for HOST in "${HOSTS_ARRAY[@]}"
do
  DATABASE="${HOST//[^a-z0-9]/_}"
  docker exec -t webserver-mysql mysql -uroot -p"$MYSQL_ROOT_PASSWORD" \
      -e "CREATE DATABASE $DATABASE;GRANT ALL PRIVILEGES ON $DATABASE.* TO '$MYSQL_USERNAME'@'%';"

  info "Database \"$DATABASE\" was created."
done
docker exec -t webserver-mysql mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "FLUSH PRIVILEGES;"

success 'Done'