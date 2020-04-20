## Docker Local environment for PHP projects

1. Create directories structure:
    ```
    /home/${USER}/webserver
    /home/${USER}/webserver/data
    /home/${USER}/webserver/data/env_files
    /home/${USER}/webserver/data/nginx
    /home/${USER}/webserver/data/nginx/config
    /home/${USER}/webserver/data/nginx/log
    /home/${USER}/webserver/data/mysql/data
    /home/${USER}/webserver/data/mysql/config
    /home/${USER}/webserver/data/composer-cache
    /home/${USER}/webserver/www
    ```
   
2. Create/pull all images:
    ```shell script
    docker build ./PHP/7.3 -t php-fpm:7.3
    docker pull nginx:1.17
    docker pull mysql:8.0
    docker pull jwilder/nginx-proxy
    ```

3. Global env settings:

    3.1. MySQL `/home/${USER}/webserver/data/env_files/mysql.env`:
    ```
    MYSQL_ROOT_PASSWORD=rootpassword
    ```
   
    3.2. nginx `/home/${USER}/webserver/data/env_files/nginx.env`:
    ```
    VIRTUAL_HOST=app-1-hostname,app-2-hostname, ...
    ```

4. Config files:

    4.1. Copy `./Nginx/http.conf` to `/home/${USER}/webserver/data/nginx/config/http.conf` and
    `./Nginx/default.conf` to `/home/${USER}/webserver/data/nginx/your-site.com.conf` 
    replacing `${HOST-NAME}` with real host of new app.
    
    4.2. Copy `./MySQL/my.cnf` to `/home/${USER}/webserver/data/mysql/config/my.cnf`.
   
5. Create containers:
    ```shell script
    cd /home/${USER}/webserver
    
    # nginx-proxy
    docker run -d \
        -p 8080:80 \
        -v /var/run/docker.sock:/tmp/docker.sock:ro \
        --name webserver-nginx-proxy \
        --net webserver-network \
        jwilder/nginx-proxy 
    
    # MySql
    docker run -d \
        -v `pwd`/data/mysql/data:/var/lib/mysql:delegated \
        -v `pwd`/data/mysql/config:/etc/mysql/conf.d:ro \
        --name webserver-mysql \
        --net webserver-network \
        --env-file `pwd`/data/env_files/mysql.env \
        mysql:8.0 \
        --default-authentication-plugin=mysql_native_password
    
    # PHP
    docker run -d \
        -v `pwd`/www:/var/www:cached \
        -v `pwd`/data/composer-cache:/home/php-user/composer-cache:delegated \
        --name webserver-php-7.3 \
        --net webserver-network \
        php-fpm:7.3
   
    # Add "--env-file `pwd`/data/env_files/php-local.env \" if you need pass env vars
    
    # nginx
    docker run -d \
        -v `pwd`/www:/var/www:cached \
        -v `pwd`/data/nginx/config:/etc/nginx/conf.d:ro \
        -v `pwd`/data/nginx/log:/var/log/nginx:delegated \
        --name webserver-nginx \
        --net webserver-network \
        --env-file `pwd`/data/env_files/nginx.env \
        nginx:1.17
    
6. Create mysql database using root mysql user:
    ```shell script
    $ docker exec -it seobar-mysql mysql -uroot -p 
    # then enter password which you specified in /home/${USER}/webserver/data/env_files/mysql.env
    ```
    ```mysql
    # Create db
    CREATE DATABASE db_name;
    
    # Create db user
    CREATE USER 'username'@'%' IDENTIFIED BY 'user_password';
    
    # Grant all privileges to username
    GRANT ALL PRIVILEGES ON db_name.* TO 'username'@'%';
    
    # Flush all privileges
    FLUSH PRIVILEGES;
    
    # check user privileges
    SHOW GRANTS FOR 'username'@'%';
    
    # The output should be:
    # +------------------------------------------------------+
    # | Grants for username@%                                |
    # +------------------------------------------------------+
    # | GRANT USAGE ON *.* TO `username`@`%`                 |
    # | GRANT ALL PRIVILEGES ON `db_name`.* TO `username`@`%`|
    # +------------------------------------------------------+
    ```