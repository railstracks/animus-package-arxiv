-- phrases list: the poll rotation + cursor position.
function run(ctx)
  local phrases = shared.load_json_state(ctx, "phrases", {})
  local cursor = tonumber(ctx.package.get_state("poll_cursor")) or 0
  local next_phrase = nil
  if #phrases > 0 then next_phrase = phrases[(cursor % #phrases) + 1] end
  return {success = true, count = #phrases, rotation = phrases,
          poll_cursor = cursor, next_phrase = next_phrase}
end