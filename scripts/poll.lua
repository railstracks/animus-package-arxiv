-- poll: new-paper check. With a 'phrase' arg, queries that phrase once
-- (rotation state untouched); otherwise rotates through the configured
-- list, one phrase per invocation. Politeness by construction: the
-- sandbox has no sleep, so the caller's cadence is the throttle (arXiv
-- asks for >= 3s between queries — schedule this no tighter than one
-- call per few minutes). New ids are recorded in 'seen' (capped at the
-- most recent 1000) and returned for the agent to triage; nothing is
-- ever auto-cached.
function run(ctx)
  local a = ctx.args or {}
  local phrases = shared.load_json_state(ctx, "phrases", {})
  local phrase, cursor, rotating
  if a.phrase ~= nil and tostring(a.phrase) ~= "" then
    phrase = tostring(a.phrase)
    rotating = false
  else
    if #phrases == 0 then
      return {success = false,
              error = "no phrases configured — use the 'phrases add' command, or pass a 'phrase' arg for a one-off check",
              state_key = "phrases"}
    end
    cursor = tonumber(ctx.package.get_state("poll_cursor")) or 0
    phrase = phrases[(cursor % #phrases) + 1]
    rotating = true
  end

  local r = ctx.http.get(shared.query_url(phrase, 0, 5, "submittedDate"),
                         {headers = shared.headers()})
  if r.status ~= 200 then
    return {success = false, error = "poll query failed: " .. shared.http_error(r),
            phrase = phrase}
  end
  local entries = shared.atom_parse(r.body)

  local seen = shared.load_json_state(ctx, "seen", {})
  local set = {}
  for _, v in ipairs(seen) do set[v] = true end
  local new = {}
  for _, e in ipairs(entries) do
    if not set[e.id] then
      set[e.id] = true
      seen[#seen + 1] = e.id
      new[#new + 1] = shared.compact(e)
    end
  end
  while #seen > 1000 do table.remove(seen, 1) end

  local ok, err = ctx.package.set_state("seen", json.encode(seen))
  if not ok then return {success = false, error = "seen persist failed: " .. tostring(err)} end

  local out = {
    success = true, phrase = phrase,
    executed_query = shared.feed_query(r.body),
    returned = #entries, new_count = #new, new_papers = new
  }
  if rotating then
    ok, err = ctx.package.set_state("poll_cursor", tostring(cursor + 1))
    if not ok then return {success = false, error = "cursor persist failed: " .. tostring(err)} end
    out.next_phrase = phrases[((cursor + 1) % #phrases) + 1]
  end
  return out
end