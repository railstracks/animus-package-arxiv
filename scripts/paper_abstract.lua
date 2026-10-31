-- paper abstract: full metadata + abstract for any paper, no cache required.
function run(ctx)
  local a = ctx.args
  if a.id == nil or a.id == "" then
    return {success = false, error = "id required (e.g. 2401.12345)"}
  end
  local r = ctx.http.get(shared.id_url(a.id), {headers = shared.headers()})
  if r.status ~= 200 then
    return {success = false, error = "fetch failed: " .. shared.http_error(r)}
  end
  local entries = shared.atom_parse(r.body)
  local e = entries[1]
  if e == nil then
    return {success = false, error = "no arxiv entry for id '" .. tostring(a.id) .. "'"}
  end
  return {
    success = true, id = e.id, title = e.title, authors = e.authors,
    published = e.published, categories = e.categories,
    primary_category = e.primary_category, summary = e.summary,
    pdf_url = e.pdf_url, abs_url = e.abs_url,
    hint = "run 'paper cache' to fetch the full text for paginated reading"
  }
end