-- arxiv / shared helpers (inlined at build time — the sandbox has no require)
--
-- No auth: arXiv's public API is credential-free. Politeness lives in the
-- command structure: one query per invocation (the sandbox has no sleep,
-- so the caller's cadence IS the throttle — Sept 13 brownout lesson from
-- the original fetcher). UA etiquette: identify the client honestly.
--
-- Lua-pattern note: `.` does not cross newlines — every multi-line span
-- below uses [%s%S] (matches everything) with lazy `-%b-` semantics.

local shared = {}

shared.UA = "animus-arxiv-package/0.1.0 (agent reading cache; contact via arxiv user)"
shared.API = "https://export.arxiv.org/api/query"
shared.HTML_BASE = "https://arxiv.org/html/"
shared.PDF_BASE = "https://arxiv.org/pdf/"

function shared.headers()
  return { ["User-Agent"] = shared.UA }
end

-- Old-style ids contain '/' (hep-th/9901001) — the fs namespace is slug-only.
function shared.safe_id(id)
  return string.gsub(tostring(id), "/", "_")
end

-- Error string for a failed HTTP result. A bare status hides the transport
-- reason: r.error carries curl's verdict; without it a stall reads as a
-- meaningless "HTTP 0" (alpaca Sept 14 lesson, shared blood).
function shared.http_error(r)
  local s = "HTTP " .. tostring(r.status)
  if r.error ~= nil and r.error ~= "" then
    s = s .. " (" .. tostring(r.error) .. ")"
  end
  return s
end

-- HTML entity decode: the named set plus numeric forms. utf8.char may be
-- absent in the sandbox (defensively guarded); numeric entities then fall
-- through undecoded — readable, not pretty.
function shared.decode_entities(s)
  if s == nil then return "" end
  s = string.gsub(s, "&amp;", "&")
  s = string.gsub(s, "&lt;", "<")
  s = string.gsub(s, "&gt;", ">")
  s = string.gsub(s, "&quot;", '"')
  s = string.gsub(s, "&apos;", "'")
  s = string.gsub(s, "&#39;", "'")
  s = string.gsub(s, "&nbsp;", " ")
  if utf8 ~= nil and utf8.char ~= nil then
    s = string.gsub(s, "&#x(%x+);", function(h) return utf8.char(tonumber(h, 16)) end)
    s = string.gsub(s, "&#(%d+);", function(d) return utf8.char(tonumber(d)) end)
  end
  return s
end

-- Tag inner text (title/summary span lines; tolerate line-broken markup).
function shared.tag(block, name)
  local v = string.match(block, "<" .. name .. "[^>]*>[%s%S]-</" .. name .. ">")
  if v == nil then return nil end
  v = string.gsub(v, "^<" .. name .. "[^>]*>", "")
  v = string.gsub(v, "</" .. name .. ">$", "")
  v = string.gsub(v, "<[^>]*>", "")
  v = string.gsub(v, "%s+", " ")
  v = string.gsub(v, "^%s", "")
  v = string.gsub(v, "%s$", "")
  return shared.decode_entities(v)
end

-- Parse an arXiv Atom feed into entries:
-- {id, title, authors[], summary, published, pdf_url, categories[], primary_category, abs_url}
function shared.atom_parse(xml)
  local entries = {}
  if xml == nil then return entries end
  for block in string.gmatch(xml, "<entry>[%s%S]-</entry>") do
    local e = {}
    local raw_id = shared.tag(block, "id") or ""
    e.id = string.match(raw_id, "/abs/([^%s]+)") or raw_id
    e.title = shared.tag(block, "title") or ""
    e.authors = {}
    for name in string.gmatch(block, "<name>([%s%S]-)</name>") do
      table.insert(e.authors, shared.decode_entities(string.gsub(name, "%s+", " ")))
    end
    e.summary = shared.tag(block, "summary") or ""
    local pub = string.match(block, "<published>([^<]+)</published>")
    e.published = pub and string.sub(pub, 1, 10) or ""
    e.pdf_url = nil
    for href in string.gmatch(block, '<link[^>]-title="pdf"[^>]-href="([^"]*)"') do
      e.pdf_url = href
    end
    for href in string.gmatch(block, '<link[^>]-href="([^"]*)"[^>]-title="pdf"') do
      e.pdf_url = href
    end
    e.categories = {}
    for term in string.gmatch(block, '<category term="([^"]*)"') do
      table.insert(e.categories, term)
    end
    e.primary_category = string.match(block, 'primary_category term="([^"]*)"')
      or (e.categories[1] or "")
    e.abs_url = "https://arxiv.org/abs/" .. e.id
    table.insert(entries, e)
  end
  return entries
end

-- Compact an entry for tool results: full identity, trimmed summary.
function shared.compact(e, summary_chars)
  local limit = summary_chars or 400
  local authors = {}
  for i = 1, math.min(3, #e.authors) do authors[i] = e.authors[i] end
  if #e.authors > 3 then authors[#authors + 1] = "et al." end
  local summary = e.summary or ""
  if #summary > limit then summary = string.sub(summary, 1, limit) .. "…" end
  return {
    id = e.id, title = e.title, authors = authors, published = e.published,
    primary_category = e.primary_category, summary = summary, pdf_url = e.pdf_url
  }
end

-- URL-encode an arXiv search query: space → '+' (arXiv's separator form),
-- everything outside unreserved (+ exempt) percent-encoded.
function shared.query_url(query, start, max_results, sort)
  local esc = string.gsub(tostring(query), " ", "+")
  esc = string.gsub(esc, "([^%w%-%.%_%~%+])", function(c)
    return string.format("%%%02X", string.byte(c))
  end)
  local url = shared.API .. "?search_query=all:" .. esc ..
    "&start=" .. tostring(start or 0) ..
    "&max_results=" .. tostring(max_results or 10)
  if sort ~= nil and sort ~= "" then
    url = url .. "&sortBy=" .. tostring(sort) .. "&sortOrder=descending"
  end
  return url
end

function shared.id_url(id)
  local esc = string.gsub(tostring(id), "([^%w%-%.%_%~])", function(c)
    return string.format("%%%02X", string.byte(c))
  end)
  return shared.API .. "?id_list=" .. esc .. "&max_results=1"
end

-- Block-close tag classification for strip_html.
local para_tags = { p = true, div = true, section = true, article = true,
  figure = true, table = true, blockquote = true, figcaption = true,
  ul = true, ol = true, dt = true, dd = true }
for i = 1, 6 do para_tags["h" .. i] = true end
local line_tags = { li = true, tr = true, td = true, th = true }

-- HTML → text. LaTeXML renderings: math alttext kept inline as $...$ LaTeX
-- (agents read LaTeX better than stripped glyphs), script/style/head and
-- comments dropped, block closes become paragraph breaks, entities decoded.
function shared.strip_html(html)
  if html == nil then return "" end
  -- arXiv LaTeXML renderings wrap the paper in exactly ONE <article> span;
  -- everything outside it is site chrome (report-issue forms, banners,
  -- nav, footers — the live 2607 page carried more than the fixture did).
  -- Prefer the article span; fall back to explicit chrome-block removal.
  local art = string.match(html, "<article[^>]*>[%s%S]-</article>")
  if art ~= nil then
    html = art
  else
    html = string.gsub(html, "<nav[^>]*>[%s%S]-</nav>", " ")
    html = string.gsub(html, "<header[^>]*>[%s%S]-</header>", " ")
    html = string.gsub(html, "<footer[^>]*>[%s%S]-</footer>", " ")
    html = string.gsub(html, "<form[^>]*>[%s%S]-</form>", " ")
  end
  html = string.gsub(html, "<script[%s%S]-</script>", " ")
  html = string.gsub(html, "<style[%s%S]-</style>", " ")
  html = string.gsub(html, "<head[^>]*>[%s%S]-</head>", " ")
  html = string.gsub(html, "<!%-%-[%s%S]-%-%->", " ")
  -- math: keep the LaTeX alttext inline if present (position-independent),
  -- then drop the whole <math>...</math> span (LaTeXML never nests math)
  html = string.gsub(html, "<math([^>]*)>[%s%S]-</math>", function(attrs)
    local alt = string.match(attrs, 'alttext="([^"]*)"')
    if alt ~= nil then return " $" .. shared.decode_entities(alt) .. "$ " end
    return " "
  end)
  html = string.gsub(html, "<annotation[%s%S]-</annotation>", " ")
  html = string.gsub(html, "<svg[%s%S]-</svg>", " ")
  html = string.gsub(html, "<img[%s%S]->", " ")
  html = string.gsub(html, "<br[%s%S]->", "\n")
  -- block closes → breaks (before generic strip; inserted text has no '<')
  html = string.gsub(html, "</(%a+)[^>]->", function(tag)
    tag = string.lower(tag)
    if para_tags[tag] then return "\n\n" end
    if line_tags[tag] then return "\n" end
    return " "
  end)
  -- remaining tags stripped (lazy to first '>' — raw '>' never appears inside a tag)
  html = string.gsub(html, "<[%s%S]->", "")
  html = shared.decode_entities(html)
  -- collapse: space runs → one; blank-line runs → one blank line; trim ends
  html = string.gsub(html, "[ \t]+", " ")
  html = string.gsub(html, " *\n *", "\n")
  html = string.gsub(html, "\n\n\n+", "\n\n")
  html = string.gsub(html, "^\n+", "")
  html = string.gsub(html, "\n+$", "")
  return html
end

-- Split text into pages of at most max_bytes, breaking at (in priority)
-- the last paragraph seam, newline, sentence end, or space in the window.
-- Returns {pages = {...}, total_chars = n}. Terminates: brk >= 1 always.
function shared.split_pages(text, max_bytes)
  local cap = max_bytes or 8192
  local pages = {}
  local pos, n = 1, #text
  while pos <= n do
    if n - pos + 1 <= cap then
      local last = string.gsub(string.sub(text, pos), "^%s+", "")
      if #last > 0 then pages[#pages + 1] = last end
      break
    end
    local window = string.sub(text, pos, pos + cap - 1)
    local brk = nil
    -- last paragraph seam
    local i = #window - 1
    while i >= 1 and brk == nil do
      if string.sub(window, i, i) == "\n" and string.sub(window, i + 1, i + 1) == "\n" then brk = i end
      i = i - 1
    end
    -- last single newline
    if brk == nil then
      i = #window
      while i >= 1 and brk == nil do
        if string.sub(window, i, i) == "\n" then brk = i end
        i = i - 1
      end
    end
    -- last sentence end
    if brk == nil then
      i = #window
      while i >= 2 and brk == nil do
        local prev = string.sub(window, i - 1, i - 1)
        if string.sub(window, i, i) == " " and (prev == "." or prev == "!") then brk = i end
        i = i - 1
      end
    end
    -- last space
    if brk == nil then
      i = #window
      while i >= 1 and brk == nil do
        if string.sub(window, i, i) == " " then brk = i end
        i = i - 1
      end
    end
    if brk == nil or brk < 1 then brk = cap end
    local chunk = string.gsub(string.sub(text, pos, pos + brk - 1), "%s+$", "")
    if #chunk > 0 then pages[#pages + 1] = chunk end
    pos = pos + brk
    while pos <= n do
      local c = string.sub(text, pos, pos)
      if c == "\n" or c == " " or c == "\t" then pos = pos + 1 else break end
    end
  end
  if #pages == 0 then pages[1] = "" end
  return { pages = pages, total_chars = n }
end

-- Load a JSON-array state key defensively (nil/""/invalid → fallback).
function shared.load_json_state(ctx, key, fallback)
  local raw = ctx.package.get_state(key)
  if raw == nil or raw == "" or raw == "***" then return fallback end
  local ok, v = pcall(json.decode_safe, raw)
  if not ok or type(v) ~= "table" then return fallback end
  return v
end

-- The library index lives in state as a JSON object keyed by arxiv id.
function shared.load_library(ctx)
  local lib = shared.load_json_state(ctx, "library", {})
  return lib
end

-- Delete all filespace artifacts of a cached paper (library entry shape).
function shared.remove_files(ctx, sid, entry)
  local n = tonumber(entry.pages) or 0
  for i = 1, n do
    ctx.fs.delete(string.format("%s-p%03d.txt", sid, i))
  end
  ctx.fs.delete(sid .. ".meta.json")
  if entry.has_pdf then ctx.fs.delete(sid .. ".pdf") end
end

return shared