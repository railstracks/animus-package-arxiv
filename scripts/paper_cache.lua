-- paper cache: fetch metadata + HTML rendering, split into text pages in the
-- package filespace, index in library state. Abstract-only fallback when no
-- HTML rendering exists. Optional PDF archival.
function run(ctx)
  local a = ctx.args
  if a.id == nil or a.id == "" then
    return {success = false, error = "id required (e.g. 2401.12345 or hep-th/9901001)"}
  end

  -- 1) metadata by id (http 1/3)
  local r = ctx.http.get(shared.id_url(a.id), {headers = shared.headers()})
  if r.status ~= 200 then
    return {success = false, error = "metadata fetch failed: " .. shared.http_error(r)}
  end
  local entries = shared.atom_parse(r.body)
  local e = entries[1]
  if e == nil then
    return {success = false, error = "no arxiv entry for id '" .. tostring(a.id) ..
      "' — check the id and version (try 'paper abstract' to verify it exists)"}
  end
  local sid = shared.safe_id(e.id)

  -- 2) HTML rendering (http 2/3) — text pages; fall back to abstract-only.
  -- Render + hash run under pcall: the sandbox instruction-count hook
  -- raises a CATCHABLE Lua error, so a budget trip on a heavy rendering
  -- degrades to an abstract-only cache flagged degraded="instruction_limit"
  -- instead of failing the run (0.1.2 field report: a 1.75MB math/tables-
  -- heavy rendering — its text is only 203KB — tripped the kernel's 10M
  -- instruction budget; body_hash now samples large bodies so the trip
  -- should not recur — this degrade is the belt-and-braces floor).
  local text, html_sha, mode, degraded
  local hr = ctx.http.get(shared.HTML_BASE .. e.id, {headers = shared.headers(), timeout_s = 60})
  if hr.status == 200 and #hr.body > 1000 then
    local ok_strip, t = pcall(shared.strip_html, hr.body)
    local ok_hash, sha = pcall(shared.body_hash, ctx, hr.body)
    if ok_strip and t ~= nil and #t > 0 and ok_hash then
      text, html_sha, mode = t, sha, "html"
    else
      degraded = (ok_strip and ok_hash) and "empty_render" or "instruction_limit"
      ctx.log("html render degraded (" .. degraded ..
              ") — caching abstract-only; web_fetch the rendering for full text")
    end
  end
  if mode == nil then
    -- no rendering, unusably short body, or render-budget trip: abstract-only
    text = e.title .. "\n\n" .. (e.summary or "")
    html_sha = nil
    mode = "abstract"
  end
  local sp = shared.split_pages(text, 8192)

  -- overwrite an existing cache of the same paper first (idempotent re-cache)
  local lib = shared.load_library(ctx)
  local old = lib[e.id]
  if old ~= nil then shared.remove_files(ctx, sid, old) end

  for i, ptext in ipairs(sp.pages) do
    local ok, err = ctx.fs.write(string.format("%s-p%03d.txt", sid, i), ptext)
    if not ok then
      return {success = false, error = "page write failed: " .. tostring(err) .. " (filespace quota?)"}
    end
  end

  -- 3) optional PDF archival (http 3/3) — binary; off by default
  local has_pdf = false
  if a.include_pdf and e.pdf_url ~= nil then
    local pr = ctx.http.get(e.pdf_url, {headers = shared.headers(), timeout_s = 120})
    if pr.status == 200 and #pr.body > 1000 then
      local ok, err = ctx.fs.write(sid .. ".pdf", pr.body)
      if ok then
        has_pdf = true
      else
        ctx.log("pdf cache write failed: " .. tostring(err))
      end
    else
      ctx.log("pdf fetch failed: " .. shared.http_error(pr) .. " — caching text pages only")
    end
  end

  local meta = {
    id = e.id, title = e.title, authors = e.authors, published = e.published,
    primary_category = e.primary_category, categories = e.categories,
    pdf_url = e.pdf_url, abs_url = e.abs_url,
    mode = mode, pages = #sp.pages, total_chars = sp.total_chars,
    html_sha256 = html_sha, has_pdf = has_pdf, cached_at = ctx.now,
    degraded = degraded
  }
  ctx.fs.write(sid .. ".meta.json", json.encode(meta))

  lib[e.id] = meta
  local ok, err = ctx.package.set_state("library", json.encode(lib))
  if not ok then
    return {success = false, error = "library persist failed: " .. tostring(err)}
  end

  local abstract = e.summary or ""
  if #abstract > 300 then abstract = string.sub(abstract, 1, 300) .. "…" end
  local out = {
    success = true, id = e.id, title = e.title, mode = mode,
    pages = #sp.pages, total_chars = sp.total_chars, pdf_cached = has_pdf,
    abstract = abstract
  }
  if degraded ~= nil then
    out.degraded = degraded
    out.note = "render budget tripped — cached abstract-only; web_fetch the HTML rendering for full text"
  end
  return out
end