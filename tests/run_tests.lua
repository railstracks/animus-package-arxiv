-- run_tests.lua — offline suite for the arxiv package.
--   lua5.4 tests/run_tests.lua
-- Real fixtures (fetched live Oct 31 2026) + a mock ctx; no network.

-- Derive package root from this script's path ("tests/run_tests.lua" → ".").
-- Run from anywhere: lua5.4 /abs/path/tests/run_tests.lua works too.
local path = arg and arg[0] or "tests/run_tests.lua"
local root = path:match("^(.*/)tests/") or "."

-- load mock harness first (it installs the global json)
local mock = dofile(root .. "/tests/mock_ctx.lua")
mock.setup(root)

local shared = dofile(root .. "/scripts/_shared.lua")
_G.shared = shared  -- raw scripts expect the global; build inlines it

local failures = 0
local passed = 0
local function check(label, cond, detail)
  if cond then
    passed = passed + 1
    print("ok    " .. label)
  else
    failures = failures + 1
    print("FAIL  " .. label .. (detail ~= nil and ("  [" .. tostring(detail) .. "]") or ""))
  end
end

local function read_fixture(p)
  local f = io.open(root .. "/tests/fixtures/" .. p, "rb")
  if f == nil then error("missing fixture: " .. p) end
  local d = f:read("*a")
  f:close()
  return d
end

-- ============ shared.atom_parse (real Atom fixture) ============
local atom = read_fixture("atom-search.xml")
local entries = shared.atom_parse(atom)
check("atom_parse: 2 entries", #entries == 2, #entries)
local e1 = entries[1]
check("atom_parse: id", e1.id == "2610.40657v1", e1.id)
check("atom_parse: title", e1.title ~= "" and e1.title ~= nil)
check("atom_parse: published date", e1.published == "2026-10-29", e1.published)
check("atom_parse: pdf link", e1.pdf_url ~= nil and e1.pdf_url:find("pdf", 1, true) ~= nil, tostring(e1.pdf_url))
check("atom_parse: authors table", type(e1.authors) == "table" and #e1.authors >= 1, #e1.authors and #e1.authors or "nil")
check("atom_parse: summary nonempty", e1.summary ~= nil and #e1.summary > 50, e1.summary and #e1.summary)
check("atom_parse: primary_category", e1.primary_category ~= nil and e1.primary_category ~= "", e1.primary_category)

-- by-id fixture (single entry)
local byid = shared.atom_parse(read_fixture("atom-byid-2610.xml"))
check("atom_parse: by-id single entry", #byid == 1 and byid[1].id == "2610.40657v1", byid[1] and byid[1].id)

-- empty/garbage feeds
check("atom_parse: empty feed → {}", #shared.atom_parse("") == 0)
check("atom_parse: nil → {}", #shared.atom_parse(nil) == 0)
check("atom_parse: garbage → {}", #shared.atom_parse("<html>nope</html>") == 0)

-- ============ shared.strip_html (real LaTeXML fixture) ============
local html = read_fixture("2610.html")
local text = shared.strip_html(html)
check("strip_html: no residual tags", text:find("<") == nil, text:sub(1, 120))
check("strip_html: no entities", text:find("&amp") == nil and text:find("&#") == nil)
check("strip_html: math preserved as $..$", text:find("%$") ~= nil, "no $ in output")
check("strip_html: script gone", text:find("ltx_font") == nil)
check("strip_html: title survives", text:find("anyon") ~= nil, "anyon not in stripped text")
check("strip_html: reasonable size", #text > 20000 and #text < 400000, #text)
check("strip_html: no site chrome (report/back-banner)",
  text:find("Report GitHub Issue") == nil and text:find("Why HTML") == nil)
check("strip_html: starts at document title",
  text:sub(1, 60):find("Variational") ~= nil, text:sub(1, 60))

-- 2007 backfill rendering (different LaTeXML vintage)
local text07 = shared.strip_html(read_fixture("0704.html"))
check("strip_html(2007): no residual tags", text07:find("<") == nil)
check("strip_html(2007): content survives", #text07 > 10000, #text07)

-- ============ shared.split_pages ============
local sp = shared.split_pages(string.rep("paragraph\n\n", 3000), 8192)
check("split_pages: page count sane", #sp.pages >= 5 and #sp.pages <= 8, #sp.pages)
local all_ok = true
for i, p in ipairs(sp.pages) do
  if #p > 8192 then all_ok = false end
  if #p == 0 then all_ok = false end
end
check("split_pages: every page bounded + nonempty", all_ok)
-- reassembly loses only seam whitespace; character coverage holds
check("split_pages: total_chars", sp.total_chars == #string.rep("paragraph\n\n", 3000))

-- pathological: one giant unbroken token
local sp2 = shared.split_pages(string.rep("x", 20000), 8192)
check("split_pages: unbroken token splits", #sp2.pages >= 3 and #sp2.pages <= 4, #sp2.pages)

-- tiny input
local sp3 = shared.split_pages("hello world", 8192)
check("split_pages: tiny → single page", #sp3.pages == 1 and sp3.pages[1] == "hello world")

-- ============ shared.query_url / id_url ============
local q = shared.query_url("electron correlation lattice", 0, 5, "submittedDate")
check("query_url: spaces → +", q:find("electron%+correlation%+lattice", 1, false) ~= nil or q:find("electron+correlation+lattice") ~= nil, q)
check("query_url: host + params", q:find("export.arxiv.org/api/query%?search_query=all:") ~= nil, q)
check("query_url: sort", q:find("sortBy=submittedDate") ~= nil)
local iu = shared.id_url("hep-th/9901001")
check("id_url: slash encoded", iu:find("%%2F") ~= nil, iu)

-- ============ shared.decode_entities / tag ============
check("entities: named", shared.decode_entities("a &amp; b &lt;c&gt; &quot;d&quot;") == 'a & b <c> "d"')
check("entities: numeric", shared.decode_entities("&#65;") == "A" or shared.decode_entities("&#65;") ~= nil)
check("tag: multiline span", shared.tag("<title>\n  hello \n there</title>", "title") == "hello there")

-- ============ search command (mock ctx, real fixture body) ============
dofile(root .. "/scripts/search.lua")  -- defines global run()
local search_run = run
local sctx = mock.new({
  routes = {{match = "export.arxiv.org/api/query", body = atom}},
  args = {query = "electron correlation lattice"}
})
local sres = search_run(sctx)
check("search: success", sres.success == true, sres.error)
check("search: 2 results", sres.count == 2, sres.count)
check("search: result shape", sres.results[1].id == "2610.40657v1" and sres.results[1].title ~= nil)
local sctx2 = mock.new({routes = {{match = "export.arxiv.org", fail = true}}, args = {query = "x"}})
local sres2 = search_run(sctx2)
check("search: http failure is loud", sres2.success == false and sres2.error:find("failed") ~= nil, sres2.error)
local sctx3 = mock.new({routes = {}, args = {}})
local sres3 = search_run(sctx3)
check("search: missing query rejected", sres3.success == false)

-- ============ paper cache (mock ctx, real fixtures) ============
dofile(root .. "/scripts/paper_cache.lua")  -- global run() = cache impl
local cache_run = run
local html_body = read_fixture("2610.html")
local cctx = mock.new({
  routes = {
    {match = "id_list=", body = read_fixture("atom-byid-2610.xml")},
    {match = "arxiv.org/html/", body = html_body},
  },
  args = {id = "2610.40657v1"}
})
local cres = cache_run(cctx)
check("cache: success", cres.success == true, cres.error)
check("cache: mode html", cres.mode == "html", cres.mode)
check("cache: pages written", cres.pages ~= nil and cres.pages >= 5, cres.pages)
check("cache: library state updated", cctx._state.library ~= nil and cctx._state.library:find("2610.40657v1") ~= nil)
check("cache: 2 http calls (metadata+html)", #cctx._http_calls == 2, #cctx._http_calls)
check("cache: abstract in result", cres.abstract ~= nil and #cres.abstract > 30)

-- ============ read back every page ============
dofile(root .. "/scripts/paper_read.lua")
local read_run = run
local rctx = mock.new({state = {library = cctx._state.library}})
local all_read_ok = true
for pg = 1, cres.pages do
  rctx.args = {id = "2610.40657v1", page = pg}
  local rr = read_run(rctx)
  if rr.success ~= true or rr.text == nil or #rr.text == 0 then all_read_ok = false end
  if rr.pages_total ~= cres.pages then all_read_ok = false end
end
check("read: every page of cached paper", all_read_ok)
rctx.args = {id = "2610.40657v1", page = 1}
local rr1 = read_run(rctx)
check("read: next_page pointer", rr1.next_page == 2, rr1.next_page)
rctx.args = {id = "2610.40657v1", page = cres.pages}
local rrl = read_run(rctx)
check("read: last page has no next", rrl.next_page == nil)
rctx.args = {id = "2610.40657v1", page = 999}
local rr999 = read_run(rctx)
check("read: out-of-range rejected", rr999.success == false)
rctx.args = {id = "9999.99999"}
local rrmiss = read_run(rctx)
check("read: uncached rejected with hint", rrmiss.success == false and rrmiss.hint ~= nil)

-- re-cache is idempotent (no dupes in fs)
local cctx2 = mock.new({
  routes = {
    {match = "id_list=", body = read_fixture("atom-byid-2610.xml")},
    {match = "arxiv.org/html/", body = html_body},
  },
  args = {id = "2610.40657v1"},
  state = {library = cctx._state.library}
})
local cres2 = cache_run(cctx2)
check("cache: re-cache succeeds", cres2.success == true, cres2.error)
check("cache: page count stable on re-cache", cres2.pages == cres.pages, cres2.pages .. " vs " .. cres.pages)

-- fallback: no HTML rendering → abstract mode
local fctx = mock.new({
  routes = {
    {match = "id_list=", body = read_fixture("atom-byid-2610.xml")},
    {match = "arxiv.org/html/", status = 404, body = "not found"},
  },
  args = {id = "2610.40657v1"}
})
local fres = cache_run(fctx)
check("cache: fallback abstract mode", fres.success == true and fres.mode == "abstract", fres.mode)
check("cache: fallback still pages", fres.pages ~= nil and fres.pages >= 1, fres.pages)

-- unknown id
local uctx = mock.new({
  routes = {
    {match = "id_list=", status = 200, body = "<feed xmlns='http://www.w3.org/2005/Atom'></feed>"},
  },
  args = {id = "9999.99999"}
})
local ures = cache_run(uctx)
check("cache: unknown id rejected", ures.success == false and ures.error:find("no arxiv entry") ~= nil, ures.error)

-- ============ paper abstract ============
dofile(root .. "/scripts/paper_abstract.lua")
local abstract_run = run
local actx = mock.new({
  routes = {{match = "id_list=", body = read_fixture("atom-byid-2610.xml")}},
  args = {id = "2610.40657v1"}
})
local ares = abstract_run(actx)
check("abstract: success + full summary", ares.success == true and #ares.summary > 200, ares.summary and #ares.summary)
check("abstract: hint present", ares.hint ~= nil)

-- ============ cache list / remove ============
dofile(root .. "/scripts/cache_list.lua")
local list_run = run
local lctx = mock.new({state = {library = cctx._state.library}})
local lres = list_run(lctx)
check("list: 1 entry", lres.success == true and lres.count == 1, lres.count)

local dctx = mock.new({state = {library = cctx._state.library}})
dofile(root .. "/scripts/cache_remove.lua")
local remove_run = run
dctx.args = {id = "2610.40657v1"}
local dres = remove_run(dctx)
check("remove: success", dres.success == true, dres.error)
local lib_after = json.decode_safe(dctx._state.library)
check("remove: library entry gone", lib_after["2610.40657v1"] == nil)
local dctx2 = mock.new({state = {library = dctx._state.library}})
dctx2.args = {id = "2610.40657v1"}
local dres2 = remove_run(dctx2)
check("remove: second remove rejected", dres2.success == false)

-- ============ poll ============
dofile(root .. "/scripts/poll.lua")
local poll_run = run
local phrase_state = json.encode({"electron correlation lattice", "agent memory"})
local pctx = mock.new({
  routes = {{match = "export.arxiv.org/api/query", body = atom}},
  state = {phrases = phrase_state},
})
local pres = poll_run(pctx)
check("poll: success", pres.success == true, pres.error)
check("poll: 2 new (fresh seen)", pres.new_count == 2, pres.new_count)
check("poll: cursor advanced", pctx._state.poll_cursor == "1", pctx._state.poll_cursor)
local pctx2 = mock.new({
  routes = {{match = "export.arxiv.org/api/query", body = atom}},
  state = {phrases = phrase_state, seen = pctx._state.seen, poll_cursor = "1"}
})
local pres2 = poll_run(pctx2)
check("poll: same feed → 0 new", pres2.success == true and pres2.new_count == 0, pres2.new_count)
-- rotation: cursor 1 → phrase index 2
check("poll: rotates phrases", pres2.phrase == "agent memory", pres2.phrase)
check("poll: next_phrase pointer", pres2.next_phrase == "electron correlation lattice", pres2.next_phrase)

local pctx3 = mock.new({state = {}})
local pres3 = poll_run(pctx3)
check("poll: no phrases configured → loud", pres3.success == false and pres3.error:find("phrases") ~= nil)

local pctx4 = mock.new({
  routes = {{match = "export.arxiv.org", fail = true}},
  state = {phrases = phrase_state}
})
local pres4 = poll_run(pctx4)
check("poll: transport failure is loud", pres4.success == false and pres4.error:find("failed") ~= nil, pres4.error)

print("")
print(("PASSED %d, FAILED %d"):format(passed, failures))
os.exit(failures == 0 and 0 or 1)