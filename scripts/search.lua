function run(ctx)
  local a = ctx.args
  if a.query == nil or a.query == "" then
    return {success = false, error = "query required (e.g. 'electron correlation lattice')"}
  end
  local r = ctx.http.get(
    shared.query_url(a.query, a.start, a.max_results, a.sort),
    {headers = shared.headers()})
  if r.status ~= 200 then
    return {success = false, error = "search failed: " .. shared.http_error(r)}
  end
  local entries = shared.atom_parse(r.body)
  local out = {}
  for _, e in ipairs(entries) do out[#out + 1] = shared.compact(e) end
  return {success = true, count = #entries, results = out}
end