#!/bin/sh
# Claude Code status line: model, context, session cost, plan spend, rate limits.
# Metrics only. Needs jq. If Orca is installed, also forwards the payload to
# Orca's managed status line script so Orca keeps working.

payload=$(cat)

# --- Forward to Orca (same path and guards as Orca's installed command) ---
orca_forward() {
  if [ -z "${HOME-}" ]; then return 0; fi
  orca_sh="${HOME-}/.orca/agent-hooks/claude-statusline.sh"
  if [ -f "$orca_sh" ] && [ -r "$orca_sh" ] && [ -x "$orca_sh" ]; then
    printf '%s' "$payload" | /bin/sh "$orca_sh" >/dev/null 2>&1 || :
  fi
}

# --- Build our line ---
line=
reset_label=$(date -v1d -v+1m '+%b %-d' 2>/dev/null || date -d "$(date +%Y-%m-01) +1 month" '+%b %-d' 2>/dev/null)
extra_usage='null'
usage_age=
# --- Plan spend (from Claude Code's own cache in ~/.claude.json; nothing is fetched) ---
if command -v jq >/dev/null 2>&1 && [ -f "${HOME-}/.claude.json" ]; then
  json_ms=$(jq -r '.cachedUsageUtilization.fetchedAtMs // 0' "${HOME-}/.claude.json" 2>/dev/null) || json_ms=0
  extra_usage=$(jq -c '.cachedUsageUtilization.utilization.extra_usage // null' "${HOME-}/.claude.json" 2>/dev/null) || extra_usage='null'
  case "$json_ms" in ''|*[!0-9]*) json_ms=0;; esac
  [ -n "$extra_usage" ] || extra_usage='null'
  now_ms=$(( $(date +%s) * 1000 ))
  if [ "$extra_usage" != 'null' ] && [ "$json_ms" -gt 0 ]; then
    age_s=$(( (now_ms - json_ms) / 1000 ))
    if [ "$age_s" -ge 300 ]; then
      if [ "$age_s" -ge 86400 ]; then usage_age="($(( age_s / 86400 ))d)"
      elif [ "$age_s" -ge 3600 ]; then usage_age="($(( age_s / 3600 ))h)"
      else usage_age="($(( age_s / 60 ))m)"; fi
    fi
  fi
fi
if command -v jq >/dev/null 2>&1 && [ -n "$payload" ]; then
  line=$(printf '%s' "$payload" | jq -r --argjson now "$(date +%s)" --arg reset_label "$reset_label" --arg usage_age "$usage_age" --argjson extra_usage "$extra_usage" '
    def red: "\u001b[31m" + . + "\u001b[0m";
    def yel: "\u001b[33m" + . + "\u001b[0m";
    def num: if type == "number" then . else null end;
    def commas:
      tostring as $s | ($s | length) as $l |
      reduce range(0; $l) as $i (""; . + (if ($i > 0 and (($l - $i) % 3) == 0) then "," else "" end) + $s[$i:$i+1]);
    def spend:
      ($extra_usage) as $eu |
      if ($eu | type) != "object" then empty else
        ($eu.used_credits | num) as $u |
        ($eu.monthly_limit | num) as $m |
        ($eu.decimal_places | num) as $dp |
        ($eu.utilization | num) as $pct |
        (if $u == null or $m == null or $dp == null or $reset_label == "" then empty else
          (pow(10; $dp)) as $div |
          (($u / $div) | round) as $ud |
          (($m / $div) | round) as $md |
          ("$" + ($ud | commas) + "/$" + ($md | commas) + " ↻" + $reset_label + (if $usage_age != "" then " " + $usage_age else "" end)) as $s |
          if ($pct != null and $pct > 80) or ($eu.spend_limit_reached == true) then ($s | red) else $s end
        end)
      end;
    def tok: if . >= 1000000 then "\((. / 100000 | floor) / 10)M"
             elif . >= 1000 then "\(. / 1000 | floor)k"
             else tostring end;
    def left($t): ($t - $now) as $s |
      if $s <= 0 then "now"
      elif $s >= 86400 then "\($s / 86400 | floor)d\(($s % 86400) / 3600 | floor)h"
      elif $s >= 3600 then "\($s / 3600 | floor)h\(($s % 3600) / 60 | floor)m"
      else "\($s / 60 | floor)m" end;
    def lim($label; $w):
      ($w.used_percentage | num) as $p |
      if $p == null then empty else
        ("\($label) \($p | floor)%" + (if ($w.resets_at | num) != null then " ↻" + left($w.resets_at) else "" end)) as $s |
        if $p > 80 then ($s | red) else $s end
      end;

    [
      (.model.display_name // empty),
      ( .context_window as $c |
        ($c.used_percentage | num) as $p |
        ($c.context_window_size | num) as $size |
        ($c.total_input_tokens | num) as $used |
        if $p == null and $used == null then empty else
          ( (if $used != null and $size != null then "\($used | tok)/\($size | tok)" else "" end)
            + (if $p != null then (if $used != null and $size != null then " " else "" end) + "\($p | floor)%" else "" end)
          ) as $s |
          ("ctx " + $s) as $s |
          if $p != null and $p > 80 then ($s | red)
          elif $p != null and $p > 60 then ($s | yel)
          else $s end
        end ),
      ( (.cost.total_cost_usd | num) as $c | if $c == null then empty else "$" + (($c * 100 | round) / 100 | tostring | if test("\\.\\d$") then . + "0" elif test("\\.") then . else . + ".00" end) end ),
      spend,
      lim("5h"; .rate_limits.five_hour // {}),
      lim("7d"; .rate_limits.seven_day // {})
    ] | map(select(. != null and . != "")) | join(" · ")
  ' 2>/dev/null) || line=
fi

[ -n "$line" ] || line="claude"
printf '%s\n' "$line"

orca_forward
exit 0
