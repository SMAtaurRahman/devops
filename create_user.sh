#!/usr/bin/env bash

set -o errexit   # abort on nonzero exitstatus
set -o nounset   # abort on unbound variable
set -o pipefail  # don't hide errors within pipes

# check if argument exists
#if [ ! -n $1 ]; then
#	echo "please enter user name as second argument"
#	exit 1
#fi

readonly USER="${1}"

echo "creating new system user: ${USER}..."

useradd "${USER}"
passwd "${USER}"

echo "assigning \"nginx\" user to \"${USER}\" group"
usermod -a -G "${USER}" "nginx"

echo "chmod /home/${USER} to 0750 (nginx can now read files)"
chmod 0750 "/home/${USER}"

##### PHP-FPM ######
echo "creating new PHP-FPM conf for ${USER}"

if [ ! -f "/etc/php-fpm.d/${USER}.conf" ]; then
	cat > "/etc/php-fpm.d/${USER}.conf" <<EOF
[${USER}]
user = ${USER}
group = ${USER}
listen = /run/php-fpm/${USER}.sock
listen.owner = ${USER}
listen.group = ${USER}
listen.mode = 0660

pm = dynamic
pm.max_children = 9999
pm.max_requests = 500
pm.start_servers = 1
pm.min_spare_servers = 1
pm.max_spare_servers = 5
php_admin_value[upload_tmp_dir] = /home/${USER}/tmp
php_admin_value[session.save_path] = /home/${USER}/tmp
php_admin_value[error_log] = /var/log/php-fpm/${USER}-error.log
php_admin_flag[log_errors] = on
EOF
fi


########### NGINX ###########
echo "creating new NGINX conf for ${USER}"

if [ ! -f "/etc/nginx/fastcgi.conf" ]; then
	cat > "/etc/nginx/fastcgi.conf" <<EOF
fastcgi_param  SCRIPT_FILENAME    \$document_root\$fastcgi_script_name;
fastcgi_param  QUERY_STRING       \$query_string;
fastcgi_param  REQUEST_METHOD     \$request_method;
fastcgi_param  CONTENT_TYPE       \$content_type;
fastcgi_param  CONTENT_LENGTH     \$content_length;

fastcgi_param  SCRIPT_NAME        \$fastcgi_script_name;
fastcgi_param  REQUEST_URI        \$request_uri;
fastcgi_param  DOCUMENT_URI       \$document_uri;
fastcgi_param  DOCUMENT_ROOT      \$document_root;
fastcgi_param  SERVER_PROTOCOL    \$server_protocol;
fastcgi_param  REQUEST_SCHEME     \$scheme;
fastcgi_param  HTTPS              \$https if_not_empty;

fastcgi_param  GATEWAY_INTERFACE  CGI/1.1;
fastcgi_param  SERVER_SOFTWARE    nginx/\$nginx_version;

fastcgi_param  REMOTE_ADDR        \$remote_addr;
fastcgi_param  REMOTE_PORT        \$remote_port;
fastcgi_param  SERVER_ADDR        \$server_addr;
fastcgi_param  SERVER_PORT        \$server_port;
fastcgi_param  SERVER_NAME        \$server_name;

# PHP only, required if PHP was built with --enable-force-cgi-redirect
fastcgi_param  REDIRECT_STATUS    200;
EOF
fi

if [ ! -f "/etc/nginx/conf.d/${USER}.conf" ]; then
	cat > "/etc/nginx/conf.d/${USER}.conf" <<EOF
server {
    server_name ${USER}.com www.${USER}.com;
    listen 80;

    root /home/${USER}/public_html;

    index index.php;

    access_log /var/log/nginx/${USER}.com_access_log;
    error_log /var/log/nginx/${USER}.com_error_log;

#    if (\$scheme = http) {
#	return 301 https://\$host\$request_uri;
#    }
#    if (\$host ~* ^www\.(.*)$) {
#	return 301 https://\$server_name\$request_uri;
#    }
    
    location / {
	try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
	try_files \$uri =404;
	include fastcgi.conf;
	
	fastcgi_pass   unix:/run/php-fpm/${USER}.sock;
    }

#    location /assets {
#        access_log off;
#        expires 60d;
#    }
   
    location = /favicon.png { access_log off; log_not_found off; expires 60d; }
    location = /favicon-apple.png { access_log off; log_not_found off; expires 60d; }
    location = /favicon.ico { access_log off; log_not_found off; expires 60d; }
    location = /robots.txt  {
	access_log off;
	log_not_found off;
    }
    
    location ~ /\.(?!well-known).* {
	deny all;
    }

    fastcgi_read_timeout 300;
}
EOF
fi


nginx -t
php-fpm -t

echo "please reload nginx & php-fpm to load new config"
