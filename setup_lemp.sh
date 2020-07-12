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
	if [[ "${OS}" = "centos" ]]; then
		dnf update -y -q
	else
		apt -qq update
		apt -qq upgrade
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
	if [[ "${OS}" = "centos" ]]; then
		dnf install "$@" -y -q
	else
		apt -qq install "$@"
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

install_epel(){
        if [[ "${OS}" = "centos" ]]; then
                if is_package_installed "remi-release"; then
                	echo "=> epel-release is already installed"
                	return 0
		fi

		install_package "epel-release"
	fi
}

install_nginx(){
	if [ -x /usr/sbin/nginx ]; then
        	echo "=> nginx is already installed"
        	return 0
	fi
	
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

	update_system
	install_package "nginx"
}

install_php(){
	if php -v 2>&1 | grep 'PHP 7.4'; then
		echo "=> PHP 7.4 is already installed"
		return 0
	fi

	if [[ "${OS}" = "centos" && "${OS_VERSION}" -eq 7 ]]; then
		if ! is_package_installed "remi-release"; then
			install_package "https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm"
			install_package "yum install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm"
			install_package "yum-utils"
			yum-config-manager --enable remi-php74
			update_system
		fi
	elif [[ "${OS}" = "centos" && "${OS_VERSION}" -eq 8 ]]; then
		if ! is_package_installed "remi-release"; then
			install_package "https://rpms.remirepo.net/enterprise/remi-release-8.rpm"
			install_package "yum-utils"
			dnf module reset php
			dnf module install php:remi-7.4

			update_system
		fi
	else
		#debian
		return 0
	fi

	install_package php php-cli php-fpm php-mysqlnd php-opcache
}

install_mariadb(){
	if [[ "${OS}" = "centos" && "${OS_VERSION}" -eq 8 ]]; then
		if [ ! -f "/etc/yum.repos.d/MariaDB.repo" ]; then 
			cat << EOF >> /etc/yum.repos.d/MariaDB.repo
[mariadb]
name = MariaDB
baseurl = https://yum.mariadb.org/10.4/centos8-amd64
gpgkey=https://yum.mariadb.org/RPM-GPG-KEY-MariaDB
gpgcheck=1
module_hotfixes=1
EOF
		fi

		install_package MariaDB-server MariaDB-client
	fi
}

config_mariadb(){
	if [ ! -f /etc/my.cnf.d/server.cnf  ]; then
		echo "/etc/my.cnf.d/server.cnf file not found"
		return 1
	fi

	if grep -q "###ATAUR-CUSTOM-CONFIG###" "/etc/my.cnf.d/server.cnf" >/dev/null 2>&1; then
		return 0
	fi

	sed -i 's+^\[mysqld\]+\[mysqld\]\ndatadir=/var/lib/mysql\nsocket=/var/lib/mysql/mysql.sock\nlog-error=/var/log/mariadb/mariadb.log\npid-file=/run/mariadb/mariadb.pid\n\n###ATAUR-CUSTOM-CONFIG###+' /etc/my.cnf.d/server.cnf
	sed -i 's/###ATAUR-CUSTOM-CONFIG###/#skip-networking\n###ATAUR-CUSTOM-CONFIG###/' /etc/my.cnf.d/server.cnf
	sed -i 's/###ATAUR-CUSTOM-CONFIG###/bind-address = 127.0.0.1\n###ATAUR-CUSTOM-CONFIG###/' /etc/my.cnf.d/server.cnf
	sed -i 's/###ATAUR-CUSTOM-CONFIG###/#sql_mode=NO_ENGINE_SUBSTITUTION,NO_AUTO_CREATE_USER\n###ATAUR-CUSTOM-CONFIG###/' /etc/my.cnf.d/server.cnf
	sed -i 's/###ATAUR-CUSTOM-CONFIG###/character-set-server=utf8\n###ATAUR-CUSTOM-CONFIG###/' /etc/my.cnf.d/server.cnf
	sed -i 's/###ATAUR-CUSTOM-CONFIG###/collation-server=utf8_general_ci\n###ATAUR-CUSTOM-CONFIG###/' /etc/my.cnf.d/server.cnf

	mkdir -p "/run/mariadb"
	chown mysql:mysql "/run/mariadb"
	
	restart_daemon "mariadb"
	echo "please run \"mariadb-secure-installation\""
}

install_firewall(){
        if [[ "${OS}" = "centos" ]]; then
        	if ! is_package_installed "firewalld"; then
			install_package "firewalld"
			enable_daemon "firewalld"
		fi
		
		echo -n "opening port for http & https...."
		firewall-cmd --remove-service=cockpit --permanent >/dev/null 2>&1
		firewall-cmd --zone=public --add-service=http --permanent >/dev/null 2>&1
		firewall-cmd --zone=public --add-service=https --permanent >/dev/null 2>&1
		# reload will print success
		firewall-cmd --reload
	fi
}

update_system

install_epel

install_nginx

install_php

install_mariadb
config_mariadb

install_firewall


enable_daemon "mariadb"
enable_daemon "nginx"
enable_daemon "php-fpm"

start_daemon "mariadb"
start_daemon "nginx"
start_daemon "php-fpm"

