dockergen: docker-gen -watch -notify "openresty -s reload" /app/nginx-containers.tmpl /etc/nginx/conf.d/containers.conf
nginx: openresty -c /etc/nginx/nginx.conf