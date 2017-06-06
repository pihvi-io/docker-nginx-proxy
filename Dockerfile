FROM openresty/openresty:alpine
MAINTAINER Onni Hakala onni@keksi.io

ARG BUILD_DEPS="gettext curl wget"
ARG RUNTIME_DEPS="libintl openssl ca-certificates bash"
ARG DOCKER_GEN_VERSION=0.7.3

RUN \
    apk add --update $RUNTIME_DEPS \
    && apk add --virtual build_deps $BUILD_DEPS \

    # Install docker-gen for templating nginx configs automatically from docker changes
    && wget --quiet https://github.com/jwilder/docker-gen/releases/download/$DOCKER_GEN_VERSION/docker-gen-alpine-linux-amd64-$DOCKER_GEN_VERSION.tar.gz \
	&& tar -C /usr/local/bin -xvzf docker-gen-alpine-linux-amd64-$DOCKER_GEN_VERSION.tar.gz \
	&& rm /docker-gen-alpine-linux-amd64-$DOCKER_GEN_VERSION.tar.gz \
    
    # Use envsubst for nginx templating
    && cp /usr/bin/envsubst /usr/local/bin/envsubst  \

    # Remove non-needed stuff
    && apk del build_deps

# Configure openresty to act like normal nginx
RUN \
	ln -s /usr/local/openresty/nginx/conf /etc/nginx \
 	&& mkdir /etc/nginx/conf.d

# Install Forego
ADD https://github.com/jwilder/forego/releases/download/v0.16.1/forego /usr/local/bin/forego
RUN chmod u+x /usr/local/bin/forego

COPY . /app/
WORKDIR /app/

COPY nginx/ /etc/nginx/

ENV DOCKER_HOST=unix:///tmp/docker.sock

# Set some configurable variables
ENV \
    # Allow bigger timeouts and max upload size to test uplouds through the proxy
    NGINX_PROXY_TIMEOUT=600 \
	NGINX_MAX_UPLOAD=2G \

    # Default Host machine IP for linux machines, this needs to be overriden with MacOS
    HOSTMACHINE_IP=172.17.42.1

VOLUME ["/etc/nginx/certs"]

ENTRYPOINT ["/app/docker-entrypoint.sh"]
CMD ["forego", "start", "-r"]
