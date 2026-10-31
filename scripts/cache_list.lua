-- cache list: everything in the local reading library.
function run(ctx)
  local lib = shared.load_library(ctx)
  local arr = {}
  for _, entry in pairs(lib) do
    arr[#arr + 1] = {
      id = entry.id, title = entry.title, mode = entry.mode,
      pages = entry.pages, total_chars = entry.total_chars,
      published = entry.published, has_pdf = entry.has_pdf or false,
      cached_at = entry.cached_at
    }
  end
  table.sort(arr, function(x, y) return tostring(x.id) < tostring(y.id) end)
  return {success = true, count = #arr, library = arr}
end