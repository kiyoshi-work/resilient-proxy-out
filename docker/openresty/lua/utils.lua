local _M = {}

-- ANSI color codes
local colors = {
    red = "\27[31m",
    yellow = "\27[33m",
    green = "\27[32m",
    blue = "\27[34m",
    magenta = "\27[35m",
    cyan = "\27[36m",
    reset = "\27[0m"
}

-- function to log with level and message
function _M.log(level, message)
    local prefix = ""
    local suffix = ""
    
    -- Add color based on log level
    if level == ngx.ERR then
        prefix = colors.red .. "[ERROR] "
        suffix = colors.reset
    elseif level == ngx.WARN then
        prefix = colors.yellow .. "[WARN] "
        suffix = colors.reset
    elseif level == ngx.INFO then
        prefix = colors.green .. "[INFO] "
        suffix = colors.reset
    elseif level == ngx.DEBUG then
        prefix = colors.blue .. "[DEBUG] "
        suffix = colors.reset
    end
    
    ngx.log(level, prefix .. message .. suffix)
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