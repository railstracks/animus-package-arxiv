-- phrases remove: drop a phrase from the rotation. Exact match only — a
-- substring near-miss is a loud error listing the rotation, not a
-- silent no-op.
function run(ctx)
  local a = ctx.args
  if a.phrase == nil or a.phrase == "" then
    return {success = false, error = "phrase required"}
  end
  local phrases = shared.load_json_state(ctx, "phrases", {})
  for i, p in ipairs(phrases) do
    if p == a.phrase then
      table.remove(phrases, i)
      local ok, err = ctx.package.set_state("phrases", json.encode(phrases))
      if not ok then
        return {success = false, error = "phrases persist failed: " .. tostring(err)}
      end
      return {success = true, removed = a.phrase, rotation_size = #phrases,
              rotation = phrases}
    end
  end
  return {success = false, error = "not in rotation: '" .. tostring(a.phrase) .. "'",
          rotation = phrases}
end