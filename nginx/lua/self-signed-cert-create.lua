local ssl = require "ngx.ssl"
local resty_lock = require "resty.lock"
local common_name = ssl.server_name()

-- If SNI was not provided just use the default certificate
if common_name == nil then
    return
end
ssl.clear_certs()

local lrucache = require "resty.lrucache"

-- Use LRU cache so we don't need to read the same certifactes all the time
-- allow up to 200 items in the cache
local cache, err = lrucache.new(500) 

-- Try cache first
local key = cache:get("key")
local cert = cache:get(common_name)
if key and cert then
    local ok, err = ssl.set_der_priv_key(key)
    if not ok then
        ngx.log(ngx.ERR, "failed to set DER priv key: ", err)
        return
    end
    local ok, err = ssl.set_der_cert(cert)
    if not ok then
        ngx.log(ngx.ERR, "failed to set DER cert: ", err)
        return
    end
end



local key_data = nil;
local f = io.open("/etc/nginx/certs/default.key", "r")
if f then
    key_data = f:read("*a")
    f:close()
end
local cert_data = nil;
local f = io.open(string.format("/etc/nginx/certs/%s.crt", common_name), "r")
if f then
    cert_data = f:read("*a")
    f:close()
end

if key_data and cert_data then
    local der_priv_key, err = ssl.priv_key_pem_to_der(key_data)
    if not der_priv_key then
        ngx.log(ngx.ERR, "failed to convert key to DER: ", err)
        return
    end
    cache:set("key", der_priv_key)
    local ok, err = ssl.set_der_priv_key(der_priv_key)
    if not ok then
        ngx.log(ngx.ERR, "failed to set DER priv key: ", err)
        return
    end

    local der_cert_chain, err = ssl.cert_pem_to_der(cert_data)
    if not der_cert_chain then
        ngx.log(ngx.ERR, "failed to convert certificate to DER: ", err)
        return
    end
    cache:set(common_name, der_cert_chain)
    local ok, err = ssl.set_der_cert(der_cert_chain)
    if not ok then
        ngx.log(ngx.ERR, "failed to set DER cert: ", err)
        return
    end
    return
end 

-- prevent creating same certificate twice using lock
local lock = resty_lock:new("https_cert_lock")
local elapsed, err = lock:lock(common_name)
if not elapsed then
        return fail("failed to acquire the lock: ", err)
end

-- Create csr file
os.execute(string.format("cd /etc/nginx/certs/ && ALTNAME='DNS:%s' openssl req -new -sha256 -key default.key -out %s.csr -subj '/O=Pihvi /CN=%s'", common_name, common_name, common_name))

-- Create the certificate
os.execute(string.format("cd /etc/nginx/certs/ && ALTNAME='DNS:%s' openssl ca -batch -config /app/openssl.cnf -extensions v3_req -keyfile ca.key -cert ca.crt -out %s.crt -infiles %s.csr", common_name, common_name, common_name))

-- Add CA certificate to the chain
os.execute(string.format("cat ca.crt >> %s.crt", common_name))

-- Read the created certificate
local f = io.open(string.format("/etc/nginx/certs/%s.crt", common_name), "r")
if f then
    cert_data = f:read("*a")
    f:close()
end

-- Use certificate with nginx
local der_priv_key, err = ssl.priv_key_pem_to_der(key_data)
if not der_priv_key then
    ngx.log(ngx.ERR, "failed to convert key to DER: ", err)
    return
end
local ok, err = ssl.set_der_priv_key(der_priv_key)
if not ok then
    ngx.log(ngx.ERR, "failed to set DER priv key: ", err)
    return
end

local der_cert_chain, err = ssl.cert_pem_to_der(cert_data)
if not der_cert_chain then
    ngx.log(ngx.ERR, "failed to convert certificate to DER: ", err)
    return
end
local ok, err = ssl.set_der_cert(der_cert_chain)
if not ok then
    ngx.log(ngx.ERR, "failed to use certificate: ", err)
    return
end

-- Release lock
local ok, err = lock:unlock()
if not ok then
    return fail("failed to unlock: ", err)
end
