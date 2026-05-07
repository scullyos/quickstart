-- Docker analogue of the kubernetes filter used by the k8s deployment.
-- Reads container_name + container_id off the bind-mounted
-- /var/lib/docker/containers/<id>/config.v2.json, since fluent-bit has no
-- built-in docker filter (only docker / docker_events INPUT plugins).
-- Records whose source path is not under that tree, or whose config.v2.json
-- is unreadable, are dropped (return code -1).

local name_cache = {}

local function read_container_name(id)
    local f = io.open("/var/lib/docker/containers/" .. id .. "/config.v2.json", "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    return string.match(content, '"Name":"/([^"]+)"')
end

function enrich_docker(tag, timestamp, record)
    local path = record["source_path"]
    if not path then return -1, timestamp, record end

    local id = string.match(path, "/var/lib/docker/containers/([%x]+)/")
    if not id then return -1, timestamp, record end

    local name = name_cache[id]
    if not name then
        name = read_container_name(id)
        if not name then return -1, timestamp, record end
        name_cache[id] = name
    end

    record["container_name"] = name
    record["container_id"] = id
    record["source_path"] = nil
    return 1, timestamp, record
end
