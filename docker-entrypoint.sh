#!/bin/bash
set -e

# Warn if the DOCKER_HOST socket does not exist
if [[ $DOCKER_HOST == unix://* ]]; then
	socket_file=${DOCKER_HOST#unix://}
	if ! [ -S $socket_file ]; then
		cat >&2 <<-EOT
			ERROR: you need to share your Docker host socket with a volume at $socket_file
			Typically you should run your jwilder/nginx-proxy with: \`-v /var/run/docker.sock:$socket_file:ro\`
			See the documentation at http://git.io/vZaGJ
		EOT
		socketMissing=1
	fi
fi

# If the user has run the default command and the socket doesn't exist, fail
if [ "$socketMissing" = 1 -a "$1" = forego -a "$2" = start -a "$3" = '-r' ]; then
	exit 1
fi

##
# Replaces ${ENV} placoholders from file with provided variables
# $1 - ':'' separated list of variables
# $2 - filename to render
##
function render_env_tmpl() {
    vars=$1
    input_file=$2
    # If filename ends with .tmpl replace it without the .tmpl
    filename=$(dirname $input_file)/$(basename $input_file .tmpl)

    tmp_file=/tmp/$(basename $filename)

    # render all provided $vars to temporary file
    envsubst "$vars" < $input_file > $tmp_file

    # replace original file with rendered file
    mv $tmp_file $filename
}

# Render environmental variables for the nginx instance before starting
VARS='$HOSTMACHINE_IP:$NGINX_PROXY_TIMEOUT:$NGINX_MAX_UPLOAD'

for conf_file in $(find /etc/nginx/ -type f  -name '*.tmpl'); do
    echo "[cont-init.d] Rendering env in $conf_file..."

    # Add helper variables for easier scripting
    export __DIR__=$(dirname $conf_file)

    VARS_TMPL=$VARS':$__DIR__'
    render_env_tmpl "$VARS_TMPL" $conf_file
done

# Create default certificate for nginx which is not used but needed for nginx to start
if [ ! -f /etc/nginx/certs/default.key ] || [ ! -f /etc/nginx/certs/default.crt ]; then
    echo "Creating default certificate and key..."
    openssl req -x509 -newkey rsa:2048 -keyout /etc/nginx/certs/default.key -out /etc/nginx/certs/default.crt -days 3650 -subj '/CN=pihvi.test' -nodes
fi

# Create serial file for openssl
if [ ! -f /etc/nginx/certs/serial ]; then
    echo "01" > /etc/nginx/certs/serial
fi

# Create a database file for openssl
if [ ! -f /etc/nginx/certs/index.txt ]; then
    touch /etc/nginx/certs/index.txt
fi

# Create attribute file for openssl database
if [ ! -f /etc/nginx/certs/index.txt.attr ]; then
    echo "unique_subject = no" > /etc/nginx/certs/index.txt.attr
fi

# Create CA certificate for signing all of the on-the-fly certificates
if [ ! -f /etc/nginx/certs/ca.key ] || [ ! -f /etc/nginx/certs/ca.crt ]; then
    openssl req -x509 -newkey rsa:2048 -days 7300 -keyout /etc/nginx/certs/ca.key \
    -out /etc/nginx/certs/ca.crt -nodes \
    -subj "/O=Pihvi CA/OU=Pihvi self-signed certificate /CN=Pihvi local development Root CA"
    cat /etc/nginx/certs/ca.key /etc/nginx/certs/ca.crt > /etc/nginx/certs/ca.pem
fi

exec "$@"