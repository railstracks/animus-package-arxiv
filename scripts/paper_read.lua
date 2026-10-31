-- paper read: one page of a cached paper (paginated; 1 page ≈ 8KB text).
function run(ctx)
  local a = ctx.args
  if a.id == nil or a.id == "" then
    return {success = false, error = "id required (e.g. 2401.12345)"}
  end
  local lib = shared.load_library(ctx)
  local entry = lib[a.id]
  if entry == nil then
    -- tolerate version-less lookups for versioned cache keys
    for k, v in pairs(lib) do
      if string.sub(k, 1, #a.id) == a.id then entry = v; break end
    end
    if entry == nil then
      return {success = false, error = "not cached — run 'paper cache' first",
              id = a.id, hint = "cache list shows what's in the library"}
    end
  end
  local page = tonumber(a.page) or 1
  local total = tonumber(entry.pages) or 1
  if page < 1 or page > total then
    return {success = false, error = "page " .. page .. " out of range 1.." .. total, pages = total}
  end
  local sid = shared.safe_id(entry.id)
  local text = ctx.fs.read(string.format("%s-p%03d.txt", sid, page))
  if text == nil then
    return {success = false, error = "page file missing — cache corrupt, re-run 'paper cache'"}
  end
  local out = {
    success = true, id = entry.id, title = entry.title, mode = entry.mode,
    page = page, pages_total = total, text = text
  }
  if page < total then out.next_page = page + 1 end
  return out
end