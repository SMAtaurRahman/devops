#!/usr/bin/env bash

set -o errexit   # abort on nonzero exitstatus
set -o nounset   # abort on unbound variable
set -o pipefail  # don't hide errors within pipes

if [[ -e /etc/debian_version ]]; then
	readonly OS="debian"
	readonly OS_VERSION=$(grep -oE '[0-9]+' /etc/debian_version | head -1)
elif [[ -e /etc/centos-release ]]; then
	readonly OS="centos"
	readonly OS_VERSION=$(grep -oE '[0-9]+' /etc/centos-release | head -1)
else
	echo "This script only supports Centos & Debian"
	exit
fi

if [[ "$EUID" -ne 0 ]]; then
	echo "This installer needs to be run with superuser privileges."
	exit
fi

update_system(){
	echo -n "=> updating system packages ..... "
	if [[ "${OS}" = "centos" && "${OS_VERSION}" -eq 8 ]]; then
		dnf update -y -q
	elif [[ "${OS}" = "centos" && "${OS_VERSION}" -eq 7 ]]; then
		yum update -y -q
	else
		apt-get -qq update
		apt-get -qq upgrade
	fi
        echo "done"
}

enable_daemon(){
	local daemon="${1}"

	systemctl enable "${daemon}"
}

disable_daemon(){
	local daemon="${1}"

	systemctl enable "${daemon}"
}

start_daemon(){
	local daemon="${1}"

	echo -n "=> starting: ${daemon}...."
	systemctl start "${daemon}"
	echo "done"
}

restart_daemon(){
	local daemon="${1}"

	echo -n "=> restarting: ${daemon}...."
	systemctl restart "${daemon}"
	echo "done"
}

stop_daemon(){
	local daemon="${1}"

	echo -n "=> stopping: ${daemon}...."
	systemctl stop "${daemon}"
	echo "done"
}

install_package(){
	echo -n "=> installing $1 ..... "
	if [[ "${OS}" = "centos" && "${OS_VERSION}" -eq 8 ]]; then
		dnf install "$@" -y -q
	elif [[ "${OS}" = "centos" && "${OS_VERSION}" -eq 7 ]]; then
		yum install "$@" -y -q > /dev/null
	else
		apt-get -qq install "$@" > /dev/null
	fi
	echo "done"
}

is_package_installed(){
	local package="${1}"
        if [[ "${OS}" = "centos" ]]; then
#                if [ -z "$(rpm -qa | grep remi-release)" ]; then
		if ! rpm -qa | grep "${package}" >/dev/null 2>&1; then
			return 1
		fi
        else
		if ! dpkg -s "${package}" >/dev/null 2>&1; then
			return 1
		fi
        fi

	return 0
}

install_dependencies(){
        if [[ "${OS}" = "centos" ]]; then
                if is_package_installed "remi-release"; then
                	echo "=> epel-release is already installed"
                	return 0
		fi

		install_package "epel-release"
		install_package "yum-utils"
	else
		install_package "apt-utils"
		install_package "lsb-release"
		install_package "gnupg2"
		install_package "apt-transport-https"
	fi

	install_package "ca-certificates"
	install_package "curl" "wget"
	install_package "git"
	install_package "pwgen"
	install_package "certbot" "python-certbot-nginx"
}

install_nginx(){
	if [ -x /usr/sbin/nginx ]; then
        	echo "=> nginx is already installed"
        	return 0
	fi
	
	if [[ "${OS}" = "centos" ]]; then
		if [ ! -f "/etc/yum.repos.d/nginx.repo" ]; then
			cat > /etc/yum.repos.d/nginx.repo <<EOL
[nginx-stable]
name=nginx stable repo
baseurl=https://nginx.org/packages/centos/\$releasever/\$basearch/
gpgcheck=1
enabled=1
gpgkey=https://nginx.org/keys/nginx_signing.key
module_hotfixes=true

[nginx-mainline]
name=nginx mainline repo
baseurl=https://nginx.org/packages/mainline/centos/\$releasever/\$basearch/
gpgcheck=1
enabled=0
gpgkey=https://nginx.org/keys/nginx_signing.key
module_hotfixes=true
EOL
		fi
	else
		wget -qO - https://nginx.org/keys/nginx_signing.key | apt-key add -
		cat > /etc/apt/sources.list.d/nginx.list <<EOL
deb https://nginx.org/packages/debian/ $(lsb_release -sc) nginx
deb-src https://nginx.org/packages/debian/ $(lsb_release -sc) nginx
EOL
		apt-get -qq autoremove "nginx" > /dev/null
		apt-get -qq --purge remove "nginx" > /dev/null
	fi

	update_system
	install_package "nginx"
}

install_php(){
	if php -v 2>&1 | grep 'PHP 7.4' > /dev/null; then
		echo "=> PHP 7.4 is already installed"
		return 0
	fi

	if [[ "${OS}" = "centos" && "${OS_VERSION}" -eq 8 ]]; then
		if ! is_package_installed "remi-release"; then
			install_package "https://rpms.remirepo.net/enterprise/remi-release-8.rpm"
			dnf module reset php
			dnf module install php:remi-7.4
		fi
	elif [[ "${OS}" = "centos" && "${OS_VERSION}" -eq 7 ]]; then
		if ! is_package_installed "remi-release"; then
			install_package "https://rpms.remirepo.net/enterprise/remi-release-7.rpm"
			yum-config-manager --enable remi-php74 > /dev/null
		fi
	else
		wget -qO - https://packages.sury.org/php/apt.gpg | apt-key add -
		cat > /etc/apt/sources.list.d/php.list <<EOL
deb https://packages.sury.org/php/ $(lsb_release -sc) main
EOL
	fi

	update_system

	if [[ "${OS}" = "centos" ]]; then
		install_package php php-common php-cli php-fpm php-mysqlnd php-opcache php-json php-mbstring php-curl
	else
		install_package php7.4 php7.4-{common,cli,fpm,mysqlnd,opcache,json,mbstring,curl}
	fi
}

config_php(){
	local ini_path="/etc/php.d/50-custom.ini"
	if [[ "${OS}" = "debian" ]]; then
		ini_path="/etc/php/7.4/fpm/conf.d/50-custom.ini"
	fi

	if [ ! -f "${ini_path}" ]; then
		cat > "${ini_path}" <<EOL
opcache.enable=1
expose_php = off
cgi.fix_pathinfo=0
EOL
	fi
}

install_mariadb(){
	if [[ "${OS}" = "centos" ]]; then
		if [ ! -f "/etc/yum.repos.d/MariaDB.repo" ]; then 
			cat << EOF >> /etc/yum.repos.d/MariaDB.repo
# http://downloads.mariadb.org/mariadb/repositories/
[mariadb]
name = MariaDB
baseurl = https://yum.mariadb.org/10.4/centos${OS_VERSION}-amd64
gpgkey=https://yum.mariadb.org/RPM-GPG-KEY-MariaDB
gpgcheck=1
module_hotfixes=1
EOF
		fi

		install_package MariaDB-server MariaDB-client
	else
		if is_package_installed "mariadb-server"; then
			echo "=> Mariadb is already installed"
			return 0
		fi

		apt-key adv --fetch-keys 'https://mariadb.org/mariadb_release_signing_key.asc' > /dev/null
		cat > /etc/apt/sources.list.d/mariadb.list <<EOL
# http://downloads.mariadb.org/mariadb/repositories/
deb [arch=amd64] http://ftp.bme.hu/pub/mirrors/mariadb/repo/10.4/debian  $(lsb_release -sc) main
deb-src [arch=amd64] http://ftp.bme.hu/pub/mirrors/mariadb/repo/10.4/debian $(lsb_release -sc) main
EOL
		update_system
		install_package mariadb-server mariadb-client
	fi
}

config_mariadb(){
	if [[ "${OS}" = "centos" ]]; then
		if [ ! -f /etc/my.cnf.d/server.cnf  ]; then
			echo "/etc/my.cnf.d/server.cnf file not found"
			return 1
		fi

		if grep -q "###ATAUR-CUSTOM-CONFIG###" "/etc/my.cnf.d/server.cnf" >/dev/null 2>&1; then
			return 0
		fi

		sed -i 's+^\[mysqld\]+\[mysqld\]\ndatadir=/var/lib/mysql/\nsocket=/var/lib/mysql/mysql.sock\nlog-error=/var/log/mariadb/mariadb.log\npid-file=/var/run/mariadb/mariadb.pid\n\n###ATAUR-CUSTOM-CONFIG###+' /etc/my.cnf.d/server.cnf
		sed -i 's/###ATAUR-CUSTOM-CONFIG###/#skip-networking\n###ATAUR-CUSTOM-CONFIG###/' /etc/my.cnf.d/server.cnf
		sed -i 's/###ATAUR-CUSTOM-CONFIG###/bind-address = 127.0.0.1\n###ATAUR-CUSTOM-CONFIG###/' /etc/my.cnf.d/server.cnf
		sed -i 's/###ATAUR-CUSTOM-CONFIG###/#sql_mode=NO_ENGINE_SUBSTITUTION,NO_AUTO_CREATE_USER\n###ATAUR-CUSTOM-CONFIG###/' /etc/my.cnf.d/server.cnf
		sed -i 's/###ATAUR-CUSTOM-CONFIG###/character-set-server=utf8\n###ATAUR-CUSTOM-CONFIG###/' /etc/my.cnf.d/server.cnf
		sed -i 's/###ATAUR-CUSTOM-CONFIG###/collation-server=utf8_general_ci\n###ATAUR-CUSTOM-CONFIG###/' /etc/my.cnf.d/server.cnf

		mkdir -p "/var/run/mariadb"
		chown mysql:mysql "/var/run/mariadb"

		restart_daemon "mariadb"
		echo "please run \"mariadb-secure-installation\""
	else
		if [ ! -d /etc/mysql/mariadb.conf.d/  ]; then
			echo "/etc/mysql/mariadb.conf.d/ directory not found"
			return 1
		fi

		if [ -f /etc/mysql/mariadb.conf.d/custom.cnf  ]; then
			return 0
		fi

		cat > "/etc/mysql/mariadb.conf.d/custom.cnf" <<EOL
[mysqld]
datadir=/var/lib/mysql/
socket=/var/run/mysqld/mysqld.sock
log-error=/var/log/mariadb/mariadb.log
pid_file=/var/run/mysqld/mysqld.pid

#skip-networking
bind-address = 127.0.0.1
sql_mode=NO_ENGINE_SUBSTITUTION,NO_AUTO_CREATE_USER
character-set-server=utf8
collation-server=utf8_general_ci
EOL
		restart_daemon "mariadb"
		echo "please run \"mariadb-secure-installation\""
	fi
}

install_firewall(){
        #if [[ "${OS}" = "centos" ]]; then
        	if ! is_package_installed "firewalld"; then
			install_package "firewalld"
			enable_daemon "firewalld"
		fi

		start_daemon "firewalld"
		
		echo -n "opening port for http & https...."
		firewall-cmd --remove-service=cockpit --permanent >/dev/null 2>&1
		firewall-cmd --zone=public --add-service=http --permanent >/dev/null 2>&1
		firewall-cmd --zone=public --add-service=https --permanent >/dev/null 2>&1
		# reload will print success
		firewall-cmd --reload
	#fi
}

install_fish(){
	if is_package_installed "fish"; then
        	echo "=> Fish shell is already installed"
        	return 0
	fi

	if [[ "${OS}" = "centos" && "${OS_VERSION}" -eq 8 ]]; then
		install_package "util-linux-user"
		wget -q https://download.opensuse.org/repositories/shells:fish:release:3/CentOS_8/shells:fish:release:3.repo -P /etc/yum.repos.d/
	elif [[ "${OS}" = "centos" && "${OS_VERSION}" -eq 7 ]]; then
		install_package "util-linux"
		wget -q https://download.opensuse.org/repositories/shells:fish:release:2/CentOS_7/shells:fish:release:2.repo -P /etc/yum.repos.d/
	elif [[ "${OS}" = "debian" ]]; then
		echo 'deb http://download.opensuse.org/repositories/shells:/fish:/release:/3/Debian_10/ /' > /etc/apt/sources.list.d/shells:fish:release:3.list
		curl -fsSL https://download.opensuse.org/repositories/shells:fish:release:3/Debian_10/Release.key | gpg --dearmor | tee /etc/apt/trusted.gpg.d/shells:fish:release:3.gpg > /dev/null
	fi

	update_system
	install_package "fish"
	chsh -s `which fish`
}

start_php_fpm(){
	if [[ "${OS}" = "debian" ]]; then
		enable_daemon "php7.4-fpm"
		start_daemon "php7.4-fpm"
	else
		enable_daemon "php-fpm"
		start_daemon "php-fpm"
	fi
}

update_system

install_dependencies

install_nginx

install_php

config_php

install_mariadb

config_mariadb

install_firewall

install_fish

enable_daemon "mariadb"
enable_daemon "nginx"

start_php_fpm

start_daemon "mariadb"
start_daemon "nginx"

echo -e "\e[32;1mLEMP setup is completed.\033[0m"

