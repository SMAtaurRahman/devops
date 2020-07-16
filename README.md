# devops
A collection of helper scripts for my personal DevOps need.

Currently, Only supports CentOS 7-8 and Debian 10.

# Usage

To setup a basic Linux + Nginx + Mariadb + PHP server
```
./setup_lemp.sh
```
installed packages:
  - Nginx Latest Stable (1.18)
  - PHP 7.4
  - MariaDB 10.4
  - firewallD
  - Fish

To create a system user and prepare base config for nginx + php-fpm
```
./create_user.sh username
```
Above script will:
  - create a user and assign password
  - chmod home dir to 750
  - add nginx user to this user-group
  - create a nginx conf for username.com
  - create a fpm conf for username.com

To create a db user and assign password + permissions to it
```
./create_db_user.sh username
```
Above script will:
  - create a db user
  - assign strong password to it
  - create a db with same name as user
  - grant permission to it
