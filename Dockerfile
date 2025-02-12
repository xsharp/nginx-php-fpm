FROM debian:buster

LABEL maintainer="Colin Wilson colin@wyveo.com"

# Let the container know that there is no tty
ENV DEBIAN_FRONTEND noninteractive
ENV NGINX_VERSION 1.21.1-1~buster
ENV php_ver 8.0
ENV php_conf /etc/php/${php_ver}/fpm/php.ini
ENV fpm_conf /etc/php/${php_ver}/fpm/pool.d/www.conf
ENV COMPOSER_VERSION 2.1.5

# Install Basic Requirements
RUN buildDeps='curl gcc make autoconf libc-dev zlib1g-dev pkg-config' \
    && set -x \
    && apt-get update \
    && apt-get install --no-install-recommends $buildDeps --no-install-suggests -q -y gnupg2 dirmngr wget apt-transport-https lsb-release ca-certificates \
    && wget -q https://nginx.org/keys/nginx_signing.key -O- | apt-key add - \
    && echo "deb http://nginx.org/packages/mainline/debian/ $(lsb_release -sc) nginx" >> /etc/apt/sources.list.d/nginx.list \
    && wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg \
    && echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list \
    && apt-get update \
    && apt-get install --no-install-recommends --no-install-suggests -q -y \
            apt-utils \
            nano \
            zip \
            unzip \
            python-pip \
            python-setuptools \
            git \
            libmemcached-dev \
            libmemcached11 \
            libmagickwand-dev \
            nginx=${NGINX_VERSION} \
            php${php_ver}-fpm \
            php${php_ver}-cli \
            php${php_ver}-bcmath \
            php${php_ver}-dev \
            php${php_ver}-common \
            php${php_ver}-opcache \
            php${php_ver}-readline \
            php${php_ver}-mbstring \
            php${php_ver}-curl \
            php${php_ver}-gd \
            php${php_ver}-imagick \
            php${php_ver}-mysql \
            php${php_ver}-zip \
            php${php_ver}-pgsql \
            php${php_ver}-intl \
            php${php_ver}-xml \
            php-pear \
    && pecl channel-update pecl.php.net \
    && pecl -d php_suffix=${php_ver} install -o -f redis memcached \
    && mkdir -p /run/php \
    && pip install wheel \
    && pip install supervisor supervisor-stdout \
    && echo "#!/bin/sh\nexit 0" > /usr/sbin/policy-rc.d \
    && rm -rf /etc/nginx/conf.d/default.conf \
    && sed -i -e "s/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/g" ${php_conf} \
    && sed -i -e "s/memory_limit\s*=\s*.*/memory_limit = 256M/g" ${php_conf} \
    && sed -i -e "s/upload_max_filesize\s*=\s*2M/upload_max_filesize = 100M/g" ${php_conf} \
    && sed -i -e "s/post_max_size\s*=\s*8M/post_max_size = 100M/g" ${php_conf} \
    && sed -i -e "s/variables_order = \"GPCS\"/variables_order = \"EGPCS\"/g" ${php_conf} \
    && sed -i -e "s/;daemonize\s*=\s*yes/daemonize = no/g" /etc/php/${php_ver}/fpm/php-fpm.conf \
    && sed -i -e "s/;catch_workers_output\s*=\s*yes/catch_workers_output = yes/g" ${fpm_conf} \
    && sed -i -e "s/pm.max_children = 5/pm.max_children = 4/g" ${fpm_conf} \
    && sed -i -e "s/pm.start_servers = 2/pm.start_servers = 3/g" ${fpm_conf} \
    && sed -i -e "s/pm.min_spare_servers = 1/pm.min_spare_servers = 2/g" ${fpm_conf} \
    && sed -i -e "s/pm.max_spare_servers = 3/pm.max_spare_servers = 4/g" ${fpm_conf} \
    && sed -i -e "s/pm.max_requests = 500/pm.max_requests = 200/g" ${fpm_conf} \
    && sed -i -e "s/www-data/nginx/g" ${fpm_conf} \
    && sed -i -e "s/^;clear_env = no$/clear_env = no/" ${fpm_conf} \
    && echo "extension=redis.so" > /etc/php/${php_ver}/mods-available/redis.ini \
    && echo "extension=memcached.so" > /etc/php/${php_ver}/mods-available/memcached.ini \
    && echo "extension=imagick.so" > /etc/php/${php_ver}/mods-available/imagick.ini \
    && ln -sf /etc/php/${php_ver}/mods-available/redis.ini /etc/php/${php_ver}/fpm/conf.d/20-redis.ini \
    && ln -sf /etc/php/${php_ver}/mods-available/redis.ini /etc/php/${php_ver}/cli/conf.d/20-redis.ini \
    && ln -sf /etc/php/${php_ver}/mods-available/memcached.ini /etc/php/${php_ver}/fpm/conf.d/20-memcached.ini \
    && ln -sf /etc/php/${php_ver}/mods-available/memcached.ini /etc/php/${php_ver}/cli/conf.d/20-memcached.ini \
    && ln -sf /etc/php/${php_ver}/mods-available/imagick.ini /etc/php/${php_ver}/fpm/conf.d/20-imagick.ini \
    && ln -sf /etc/php/${php_ver}/mods-available/imagick.ini /etc/php/${php_ver}/cli/conf.d/20-imagick.ini \
    # Install Composer
    && curl -o /tmp/composer-setup.php https://getcomposer.org/installer \
    && curl -o /tmp/composer-setup.sig https://composer.github.io/installer.sig \
    && php -r "if (hash('SHA384', file_get_contents('/tmp/composer-setup.php')) !== trim(file_get_contents('/tmp/composer-setup.sig'))) { unlink('/tmp/composer-setup.php'); echo 'Invalid installer' . PHP_EOL; exit(1); }" \
    && php /tmp/composer-setup.php --no-ansi --install-dir=/usr/local/bin --filename=composer --version=${COMPOSER_VERSION} \
    && rm -rf /tmp/composer-setup.php \
    # Clean up
    && rm -rf /tmp/pear \
    && apt-get purge -y --auto-remove $buildDeps \
    && apt-get clean \
    && apt-get autoremove \
    && rm -rf /var/lib/apt/lists/*

# Supervisor config
COPY ./supervisord.conf /etc/supervisord.conf

# Override nginx's default config
COPY ./default.conf /etc/nginx/conf.d/default.conf

# Override default nginx welcome page
COPY html /usr/share/nginx/html

# Copy Scripts
COPY ./start.sh /start.sh

EXPOSE 80

CMD ["/start.sh"]
