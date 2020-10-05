#!/usr/bin/env bash

set -o errexit   # abort on nonzero exitstatus
set -o nounset   # abort on unbound variable
set -o pipefail  # don't hide errors within pipes

if [[ "$EUID" -ne 0 ]]; then
	echo "This installer needs to be run with superuser privileges."
	exit
fi

function query(){
	mysql --execute="$1"
}

readonly USER="$1"
readonly PASSWORD="$(pwgen 16 1)"

if [ -z "${PASSWORD}" ]; then
	echo "package \"pwgen\" is required to generate secure password"
	echo "please install \"pwgen\" and try again"
	exit 1
fi

echo "creating mysql user: '${USER}' with password:'${PASSWORD}'"

query "CREATE DATABASE ${USER};"

query "CREATE USER '${USER}'@localhost IDENTIFIED BY '${PASSWORD}';"

#query "GRANT USAGE ON *.* TO '$user'@localhost IDENTIFIED BY '$password';"

query "GRANT ALL privileges ON ${USER}.* TO '${USER}'@localhost;"

query "FLUSH PRIVILEGES;"

query "SHOW GRANTS FOR '${USER}'@localhost;"

query "select host, user from mysql.user;"
