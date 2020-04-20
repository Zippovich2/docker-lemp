FROM php:7.3-fpm

# Server Installs
RUN apt-get update && apt-get install -y \
    zip unzip git curl wget nano rsync inotify-tools \
    libmagickwand-dev zlib1g-dev libicu-dev libxslt-dev g++ \
    --no-install-recommends

#<-- START PHP Installs -->#

# Install imagick
RUN pecl install imagick && \
    docker-php-ext-enable imagick

# Install PDO MySql and mysqli
RUN docker-php-ext-install pdo_mysql && \
    docker-php-ext-install mysqli

# Install intl extension
RUN docker-php-ext-configure intl && \
    docker-php-ext-install intl

# Install xsl extension
RUN docker-php-ext-install xsl

RUN pecl install xdebug && \
    docker-php-ext-enable xdebug

#<-- END PHP Installs -->#

# Composer Install
RUN php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');" && \
    php composer-setup.php -- --install-dir=/usr/local/bin --filename=composer && \
    php -r "unlink('composer-setup.php');"

# php.ini settings
COPY ./php.ini $PHP_INI_DIR

# Create php-user
RUN useradd -m php-user -G www-data

WORKDIR /var/www

USER php-user