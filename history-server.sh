#!/bin/bash

set -ue

# make sure we are in the right folder
cd "$(dirname ${BASH_SOURCE[0]})"

if ! [ -a secret ]
then
	echo 'Create secret file with your password, and run "chmod 400 secret"'
	exit 1
fi
if [[ $(expr $(stat -c %a secret 2> /dev/null || stat -f%A secret 2> /dev/null || echo stat failed) % 100) != '0' ]]
then
	echo 'Run "chmod 400 secret" - file should only be readable by you'
	exit 1
fi

LISTEN_PORT=${1:-8456}

# Check socat is there
which socat > /dev/null 2>&1 || (echo socat should be installed && exit 1)

cat > writer.sh <<- 'END'
	#!/bin/bash
	read password
	# Remove whitespace from end of password (eg when using telnet)
	password="${password%"${password##*[![:space:]]}"}" 
	# Password failure
	SECRET="$(cat secret)"
	if [[ ${password} != ${SECRET} ]]
	then
		echo 'Password failure'
		echo "Password failure: ${password} ${SECRET}" >> history-server.log
		exit 1
	fi
	touch history.dat
	while read input
	do
		if [[ $input = '' ]]
		then
			cat history.dat
		fi
		echo $input >> history.dat
	done
END
chmod +x writer.sh

socat -vvv TCP-LISTEN:${LISTEN_PORT},reuseaddr,fork SYSTEM:$(pwd)/writer.sh &
SOCATPID="$!"


function cleanup() {
	rm -f writer.sh
	kill ${SOCATPID} >/dev/null 2>&1 || return > /dev/null 2>&1
	sleep 10
	if ps -p ${SOCATPID} > /dev/null 2>&1
	then
		kill -9 ${SOCATPID}
	fi
}

trap cleanup EXIT INT TERM

wait