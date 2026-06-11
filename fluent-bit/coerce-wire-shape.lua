-- Defense-in-depth: coerce any record that is not already in the expected
-- structured log shape, so Elasticsearch never receives a bare record. A
-- conforming record carries a valid `severity` and passes through untouched;
-- anything else (a log line whose `log` field failed JSON parse) is wrapped
-- with safe defaults and tagged context=fluent-bit-coerced so the off-format
-- source stays findable.

local VALID_SEVERITY = { debug = true, log = true, warn = true, error = true }

function coerce_wire_shape(tag, timestamp, record)
    if record["severity"] ~= nil and VALID_SEVERITY[record["severity"]] then
        return 0, timestamp, record
    end

    local message = record["log"] or record["message"] or ""
    record["message"] = message
    record["log"] = nil
    record["severity"] = "warn"
    record["ms"] = record["ms"] or "unknown"
    record["msreqid"] = "no-ms-id"
    record["entityType"] = "no-entity-type"
    record["entityId"] = "no-entity-id"
    record["context"] = "fluent-bit-coerced"
    return 1, timestamp, record
end
