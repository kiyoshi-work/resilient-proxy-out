local utils = require "utils"
local api_stats = require "api_stats"
local cjson = require "cjson"

-- Main function to handle the request
local function main()
    -- Get query parameters
    local args = ngx.req.get_uri_args()
    local api_name = args.api
    local path = args.path
    local period = args.period or "all"  -- all, daily, hourly
    
    if not api_name then
        -- Return list of all APIs
        local api_names = api_stats.get_api_names()
        
        -- Ensure api_names is an array, not a table with non-numeric keys
        local apis_array = {}
        for _, name in pairs(api_names) do
            table.insert(apis_array, name)
        end
        
        utils.json_response({
            timestamp = ngx.time(),
            apis = apis_array
        })
        return
    end
    
    if api_name and not path then
        -- If path is not specified but we have a 'paths' parameter, return list of paths
        if args.paths then
            local paths = api_stats.get_api_paths(api_name)
            
            -- Ensure paths is an array
            local paths_array = {}
            for _, path in pairs(paths) do
                table.insert(paths_array, path)
            end
            
            utils.json_response({
                timestamp = ngx.time(),
                api = api_name,
                paths = paths_array
            })
            return
        end
        
        -- Get statistics for the specified API
        local stats, err = api_stats.get_api_stats(api_name, period)
        
        if not stats then
            utils.json_response({
                error = err or "Failed to retrieve statistics"
            }, 500)
            return
        end
        
        -- Return the response
        utils.json_response({
            timestamp = ngx.time(),
            api = api_name,
            period = period,
            stats = stats
        })
    else
        -- Get statistics for the specified API path
        local stats, err = api_stats.get_path_stats(api_name, path, period)
        
        if not stats then
            utils.json_response({
                error = err or "Failed to retrieve path statistics"
            }, 500)
            return
        end
        
        -- Return the response
        utils.json_response({
            timestamp = ngx.time(),
            api = api_name,
            path = path,
            period = period,
            stats = stats
        })
    end
end

-- Execute the main function
main() 