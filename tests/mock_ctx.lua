-- mock_ctx.lua — offline test double for the Animus package sandbox.
--
-- Provides: global `json` (vendored rxi), a fixture-backed http.get, a
-- temp-dir fs honoring the kernel's slug rules, a table-backed package
-- state store, a content-derived fake sha256, ctx.log, ctx.now.
--
-- Usage: local ctx = mock_ctx.new({routes = {...}, state = {...}})

local mock = {}

mock.script_dir = (... and select(1, ...) and nil) -- unused; tests call via dofile path munging

-- path resolution for dofile-style loading: tests pass their dir explicitly.
function mock.setup(json_dir)
  -- vendored json with the sandbox's decode_safe alias
  local j = dofile(json_dir .. "/tests/vendor/json.lua")
  json = {
    encode = j.encode,
    decode = j.decode,
    decode_safe = function(s)
      local ok, v = pcall(j.decode, s)
      if not ok then return nil end
      return v
    end
  }
end

-- content-derived stand-in digest (64 hex chars) — tests never verify the
-- real sha; they verify it's recorded and stable.
local function fake_sha256(s)
  local h = 5381
  for i = 1, #s do
    h = ((h * 33) + string.byte(s, i)) % 2147483647
  end
  local hex = string.format("%x", h)
  while #hex < 64 do hex = hex .. string.format("%x", (h + #hex) % 2147483647) end
  return string.sub(hex, 1, 64)
end

local function valid_slug(name)
  if name == nil or #name == 0 or #name > 128 then return false end
  if string.sub(name, 1, 1) == "." then return false end
  return string.match(name, "^[%w%.%-_]+$") ~= nil
end

-- fs backend over a directory (created by caller). Mirrors kernel semantics:
-- write returns (path, nil) or (nil, err); read returns nil when missing;
-- list returns {name,size,mtime} rows.
local function make_fs(dir, quota_bytes)
  local fs = {}
  local function p(name) return dir .. "/" .. name end
  local function usage()
    local total = 0
    for f in io.popen("ls -l " .. dir .. " 2>/dev/null"):lines() do
      local size = tonumber(string.match(f, "^(%-)%s+(%d+)") or string.match(f, "%s(%d+)%s+%a"))
      if size then total = total + size end
    end
    return total
  end
  fs.write = function(name, data)
    if not valid_slug(name) then return nil, "invalid file name (slug chars only, no leading dot)" end
    local f = io.open(p(name), "wb")
    if f == nil then return nil, "open failed" end
    f:write(data)
    f:close()
    return p(name), nil
  end
  fs.read = function(name)
    if not valid_slug(name) then return nil end
    local f = io.open(p(name), "rb")
    if f == nil then return nil end
    local data = f:read("*a")
    f:close()
    return data
  end
  fs.delete = function(name)
    if not valid_slug(name) then return false end
    return os.remove(p(name)) ~= nil
  end
  fs.stat = function(name)
    if not valid_slug(name) then return nil end
    local f = io.open(p(name), "rb")
    if f == nil then return nil end
    local size = f:seek("end")
    f:close()
    return {size = size, mtime = os.time() * 1000}
  end
  fs.list = function()
    local rows = {}
    for name in io.popen("ls -1 " .. dir .. " 2>/dev/null"):lines() do
      local st = fs.stat(name)
      if st then
        rows[#rows + 1] = {name = name, size = st.size, mtime = st.mtime}
      end
    end
    return rows
  end
  return fs
end

-- routes: list of {match = function(url) -> bool | pattern string, status = n, body = str}
-- A route may be a string pattern (string.match against url) or a function.
function mock.new(opts)
  opts = opts or {}
  local state = opts.state or {}
  local http_calls = {}

  local ctx = {}
  ctx.now = opts.now or 1730700000000

  -- package state store (kernel keeps strings; tests seed strings too)
  local pkg = {}
  pkg.get_state = function(k) return state[k] end
  pkg.set_state = function(k, v)
    state[k] = v
    return true, nil
  end
  ctx.package = pkg

  -- http: sequential route matching; records every call
  ctx.http = {}
  ctx.http.get = function(url, o)
    http_calls[#http_calls + 1] = url
    for _, route in ipairs(opts.routes or {}) do
      local hit
      if type(route.match) == "function" then
        hit = route.match(url)
      else
        hit = string.find(url, route.match, 1, true) ~= nil
      end
      if hit then
        if route.fail then
          return {status = route.status or 0, error = route.error or "mock transport failure", body = ""}
        end
        return {status = route.status or 200, body = route.body or "", headers = route.headers or {}}
      end
    end
    return {status = 404, error = "mock: no route for " .. url, body = ""}
  end

  ctx.fs = make_fs(opts.fs_dir or "/tmp/mock-pkg-fs", opts.quota_bytes)
  ctx.crypto = {sha256 = fake_sha256}
  ctx.log = function(msg) io.stderr:write("[log] " .. tostring(msg) .. "\n") end
  ctx.args = opts.args or {}
  ctx.event = opts.event

  ctx._state = state
  ctx._http_calls = http_calls
  return ctx
end

return mock