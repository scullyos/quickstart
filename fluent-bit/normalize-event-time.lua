-- Sets the record's event time from the app-emitted `timestamp` field when it
-- parses as ISO-8601; otherwise keeps the capture time fluent-bit set at input.
-- The json parser does structural extraction only (no Time_Key), so a malformed
-- timestamp can never fail the parse and blank the record — this filter is what
-- restores app-emitted event time when it IS valid, with a safe fallback.

local function local_utc_offset()
    return os.difftime(os.time(os.date("*t")), os.time(os.date("!*t")))
end

local function parse_iso8601(ts)
    if type(ts) ~= "string" then return nil end
    local y, mo, d, h, mi, s, frac, tz = string.match(
        ts, "^(%d%d%d%d)%-(%d%d)%-(%d%d)[Tt ](%d%d):(%d%d):(%d%d)(%.?%d*)([Zz%+%-]?[%d:]*)$")
    if not y then return nil end

    local epoch = os.time({
        year = tonumber(y), month = tonumber(mo), day = tonumber(d),
        hour = tonumber(h), min = tonumber(mi), sec = tonumber(s), isdst = false,
    })
    if not epoch then return nil end
    -- os.time read the fields as local time; shift to a true UTC epoch.
    epoch = epoch + local_utc_offset()

    -- Apply the timestamp's own offset (Z / +00:00 / -05:00 / +0530).
    if tz ~= "" and tz ~= "Z" and tz ~= "z" then
        local sign, oh, om = string.match(tz, "([%+%-])(%d%d):?(%d*)")
        if sign then
            local off = tonumber(oh) * 3600 + (tonumber(om) or 0) * 60
            epoch = (sign == "+") and (epoch - off) or (epoch + off)
        end
    end

    local fraction = 0
    if frac ~= "" and frac ~= "." then
        fraction = tonumber("0" .. frac) or 0
    end
    return epoch + fraction
end

function normalize_event_time(tag, timestamp, record)
    local ok, parsed = pcall(parse_iso8601, record["timestamp"])
    if ok and parsed then
        return 1, parsed, record
    end
    return 0, timestamp, record
end
