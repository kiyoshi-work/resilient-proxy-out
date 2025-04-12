local _M = {}

-- function to log with level and message
function _M.log(level, message)
    ngx.log(level, message)
end

-- function to check and parse JSON
function _M.parse_json(str)
    local cjson = require "cjson"
    local success, result = pcall(cjson.decode, str)
    if not success then
        return nil, "Invalid JSON"
    end
    return result
end

-- function to create JSON response
function _M.json_response(data, status)
    local cjson = require "cjson"
    status = status or 200
    ngx.status = status
    ngx.header.content_type = "application/json"
    ngx.say(cjson.encode(data))
    return ngx.exit(status)
end

return _M