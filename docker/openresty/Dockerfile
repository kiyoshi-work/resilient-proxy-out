FROM openresty/openresty:alpine


# Install required packages including Lua development headers
RUN apk add --no-cache \
    curl \
    git \
    build-base \
    ca-certificates \
    openssl \
    openssl-dev \
    lua5.1-dev \
    luajit-dev \
    luarocks

# Update CA certificates
RUN update-ca-certificates

# Install lua-resty-redis directly from source
RUN mkdir -p /usr/local/openresty/lualib/resty \
    && cd /tmp \
    && git clone https://github.com/openresty/lua-resty-redis.git \
    && cp -R lua-resty-redis/lib/resty/* /usr/local/openresty/lualib/resty/ \
    && rm -rf /tmp/lua-resty-redis

# Install lua-resty-http for making HTTP requests
RUN cd /tmp \
    && git clone https://github.com/ledgetech/lua-resty-http.git \
    && cp -R lua-resty-http/lib/resty/* /usr/local/openresty/lualib/resty/ \
    && rm -rf /tmp/lua-resty-http

# Install lua-resty-openssl for SSL support
RUN cd /tmp \
    && git clone https://github.com/fffonion/lua-resty-openssl.git \
    && cp -R lua-resty-openssl/lib/resty/* /usr/local/openresty/lualib/resty/ \
    && rm -rf /tmp/lua-resty-openssl

# create necessary directory
RUN mkdir -p /usr/local/openresty/lua

# copy config files
COPY nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
COPY conf.d/ /usr/local/openresty/nginx/conf/conf.d/
COPY lua/ /usr/local/openresty/lua/

# check config
RUN openresty -t

# Expose port
EXPOSE 8080


# Configure logging to stdout/stderr for Docker
RUN mkdir -p /var/log/nginx && \
    ln -sf /dev/stdout /var/log/nginx/access.log && \
    ln -sf /dev/stderr /var/log/nginx/error.log

# start OpenResty
CMD ["openresty", "-g", "daemon off;"]