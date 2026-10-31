-- cache remove: delete a paper's pages, meta, and optional pdf from the
-- filespace, and drop it from the library index.
function run(ctx)
  local a = ctx.args
  if a.id == nil or a.id == "" then
    return {success = false, error = "id required (e.g. 2401.12345)"}
  end
  local lib = shared.load_library(ctx)
  local key = a.id
  local entry = lib[key]
  if entry == nil then
    for k, v in pairs(lib) do
      if string.sub(k, 1, #a.id) == a.id then key = k; entry = v; break end
    end
  end
  if entry == nil then
    return {success = false, error = "not cached: '" .. tostring(a.id) .. "'"}
  end
  shared.remove_files(ctx, shared.safe_id(entry.id), entry)
  lib[key] = nil
  local ok, err = ctx.package.set_state("library", json.encode(lib))
  if not ok then
    return {success = false, error = "library persist failed: " .. tostring(err)}
  end
  return {success = true, removed = key, pages_removed = tonumber(entry.pages) or 0}
end