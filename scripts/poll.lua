-- poll: one phrase per invocation, rotating through the configured list.
-- Politeness by construction: the sandbox has no sleep, so the caller's
-- cadence is the throttle (arXiv asks >= 3s between queries — schedule this
-- no tighter than one poll per few minutes). New ids are recorded in
-- 'seen' (capped at the most recent 1000) and returned for the agent to
-- triage; nothing is auto-cached.
function run(ctx)
  local phrases = shared.load_json_state(ctx, "phrases", {})
  if #phrases == 0 then
    return {success = false,
            error = "no phrases configured — set state 'phrases' to a JSON array of search queries",
            state_key = "phrases"}
  end
  local cursor = tonumber(ctx.package.get_state("poll_cursor")) or 0
  local idx = (cursor % #phrases) + 1
  local phrase = phrases[idx]

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
  ok, err = ctx.package.set_state("poll_cursor", tostring(cursor + 1))
  if not ok then return {success = false, error = "cursor persist failed: " .. tostring(err)} end

  local next_idx = ((cursor + 1) % #phrases) + 1
  return {
    success = true, phrase = phrase, returned = #entries,
    new_count = #new, new_papers = new, next_phrase = phrases[next_idx]
  }
end