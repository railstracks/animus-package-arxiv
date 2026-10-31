-- phrases add: append a search phrase to the poll rotation.
-- Agent self-configuration — no admin state access needed.
function run(ctx)
  local a = ctx.args
  if a.phrase == nil or a.phrase == "" then
    return {success = false, error = "phrase required"}
  end
  local phrases = shared.load_json_state(ctx, "phrases", {})
  for _, p in ipairs(phrases) do
    if p == a.phrase then
      return {success = false, error = "already in rotation", phrase = a.phrase,
              rotation = phrases}
    end
  end
  phrases[#phrases + 1] = tostring(a.phrase)
  local ok, err = ctx.package.set_state("phrases", json.encode(phrases))
  if not ok then
    return {success = false, error = "phrases persist failed: " .. tostring(err)}
  end
  return {success = true, added = a.phrase, rotation_size = #phrases,
          rotation = phrases}
end