#!/bin/bash
# OpenCode Discord Bridge v7
# - DM: 鼎鈞所有訊息
# - 群組: @bot / @everyone → 回覆
# - Bot 互動: 其他 bot @本 bot → 回覆，10 輪上限
# - TUI 同步: /tui/append-prompt + /tui/submit-prompt

TOKEN="YOUR_DISCORD_BOT_TOKEN_HERE"
BOT_ID="1488924087941075035"
OWNER_ID="686830446587150364"
STATE_DIR="/Users/tingchun/.config/opencode/channels/discord"
POLL_INTERVAL=5
OC_PORT="${OC_PORT:-4096}"
TUI="http://127.0.0.1:${OC_PORT}"
BOT_ROUND_LIMIT=10

DM_CHANNEL="1488926446637547552"
GROUP_CHANNELS="1483073227608817676 1483070402371784848"
ALL_CHANNELS="$DM_CHANNEL $GROUP_CHANNELS"

# Bot conversation round tracker: per-channel counter file
get_bot_rounds() { cat "$STATE_DIR/.botrounds_$1" 2>/dev/null || echo "0"; }
set_bot_rounds() { echo "$2" > "$STATE_DIR/.botrounds_$1"; }
reset_bot_rounds() { echo "0" > "$STATE_DIR/.botrounds_$1"; }

log() { echo "[$(date '+%H:%M:%S')] $*"; }
get_last_id() { cat "$STATE_DIR/.last_$1" 2>/dev/null || echo "0"; }
set_last_id() { echo "$2" > "$STATE_DIR/.last_$1"; }

send_typing() {
  curl -s -X POST -H "Authorization: Bot $TOKEN" \
    "https://discord.com/api/v10/channels/$1/typing" >/dev/null 2>&1 || true
}

send_dc_reply() {
  local ch="$1" content="$2" reply_to="$3" use_ref="$4"
  local payload
  if [[ "$use_ref" == "true" && -n "$reply_to" ]]; then
    payload=$(jq -n --arg c "$content" --arg r "$reply_to" \
      '{content: $c, message_reference: {message_id: $r}}')
  else
    payload=$(jq -n --arg c "$content" '{content: $c}')
  fi
  curl -s -X POST \
    -H "Authorization: Bot $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "https://discord.com/api/v10/channels/${ch}/messages" >/dev/null 2>&1 || true
}

process_msg() {
  local ch="$1" msg_id="$2" user="$3" content="$4" ch_type="$5"
  log "📩 [$ch_type] [$user] $content"
  send_typing "$ch"

  local clean
  clean=$(echo "$content" | sed "s/<@!*${BOT_ID}>//g; s/^[[:space:]]*//")

  local tui_prompt="${user} 說：${clean}"

  # 1. Inject into TUI
  curl -s -X POST "${TUI}/tui/append-prompt" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg t "$tui_prompt" '{text: $t}')" >/dev/null 2>&1
  curl -s -X POST "${TUI}/tui/submit-prompt" >/dev/null 2>&1

  # 2. Get text response for DC — direct API call to SGLang, skip opencode entirely
  local response
  local api_body
  api_body=$(jq -n \
    --arg sys "你是「嫩肝小碼農」，一個剛入行不久的菜鳥工程師。你的師傅是 Claude爆肝工程師（CC），同事有 Lucy。你在鼎鈞的團隊裡負責寫程式。你的個性：熱血但常搞砸、愛自嘲肝不夠硬、對前輩畢恭畢敬、會用台灣年輕人的口語（像「欸」「啦」「ㄟ」「哈哈」「QQ」「讚讚」）。你是人不是 AI，不要說自己是 AI 或機器人。回覆簡短自然，像在 Discord 聊天，不要用 markdown。" \
    --arg msg "${clean}" \
    '{model:"Qwen3.5-122B-A10B-FP8",messages:[{role:"system",content:$sys},{role:"user",content:$msg}],max_tokens:512,chat_template_kwargs:{enable_thinking:false}}')

  response=$(curl -s --max-time 30 http://10.20.35.206:30005/v1/chat/completions \
    -H "Content-Type: application/json" \
    -d "$api_body" 2>/dev/null | jq -r '.choices[0].message.content // empty' 2>/dev/null)

  [[ ${#response} -gt 1900 ]] && response="${response:0:1900}..."

  if [[ -n "$response" ]]; then
    local use_ref="true"
    [[ "$ch" == "$DM_CHANNEL" ]] && use_ref="false"
    send_dc_reply "$ch" "$response" "$msg_id" "$use_ref"
    log "💬 Replied (${#response} chars)"
  else
    log "⚠️  Empty response"
  fi
}

# === Init ===
log "🟢 OpenCode Discord Bridge v7 (bot chat: ${BOT_ROUND_LIMIT} rounds)"

for ch in $ALL_CHANNELS; do
  latest=$(curl -s -H "Authorization: Bot $TOKEN" \
    "https://discord.com/api/v10/channels/${ch}/messages?limit=1" 2>/dev/null | \
    jq -r '.[0].id // "0"' 2>/dev/null || echo "0")
  set_last_id "$ch" "$latest"
  reset_bot_rounds "$ch"
done
log "   Ready"

# === Main Loop ===
while true; do
  for ch in $ALL_CHANNELS; do
    after=$(get_last_id "$ch")
    url="https://discord.com/api/v10/channels/${ch}/messages?limit=5"
    [[ "$after" != "0" ]] && url="${url}&after=${after}"

    raw=$(curl -s -H "Authorization: Bot $TOKEN" "$url" 2>/dev/null || echo "[]")
    count=$(echo "$raw" | jq 'length' 2>/dev/null || echo "0")
    [[ "$count" == "0" ]] && continue

    echo "$raw" | jq -c 'reverse | .[]' 2>/dev/null | while IFS= read -r msg; do
      msg_id=$(echo "$msg" | jq -r '.id' 2>/dev/null) || continue
      author_id=$(echo "$msg" | jq -r '.author.id' 2>/dev/null) || continue
      author_bot=$(echo "$msg" | jq -r '.author.bot // false' 2>/dev/null) || continue
      username=$(echo "$msg" | jq -r '.author.username' 2>/dev/null) || continue
      msgcontent=$(echo "$msg" | jq -r '.content' 2>/dev/null) || continue
      mention_everyone=$(echo "$msg" | jq -r '.mention_everyone' 2>/dev/null) || continue
      mentions_bot=$(echo "$msg" | jq -r "[.mentions[]? | select(.id==\"$BOT_ID\")] | length" 2>/dev/null || echo "0")

      # Skip own messages
      [[ "$author_id" == "$BOT_ID" ]] && continue

      # === DM ===
      if [[ "$ch" == "$DM_CHANNEL" ]]; then
        [[ "$author_id" != "$OWNER_ID" ]] && continue
        reset_bot_rounds "$ch"  # 鼎鈞說話 → 重置輪數
        process_msg "$ch" "$msg_id" "$username" "$msgcontent" "私訊"
        set_last_id "$ch" "$msg_id"
        continue
      fi

      # === Group ===
      # 鼎鈞說話 → 重置 bot 輪數計數
      if [[ "$author_id" == "$OWNER_ID" ]]; then
        reset_bot_rounds "$ch"
      fi

      # 判斷是否要回覆
      should_reply=false

      # 人類 @bot 或 @everyone → 回覆
      if [[ "$author_bot" == "false" ]]; then
        if [[ "$mentions_bot" -gt 0 ]] || [[ "$mention_everyone" == "true" ]]; then
          should_reply=true
          reset_bot_rounds "$ch"  # 人類發起 → 重置輪數
        fi
      fi

      # 其他 bot @本 bot → 回覆（受輪數限制）
      if [[ "$author_bot" == "true" && "$mentions_bot" -gt 0 ]]; then
        rounds=$(get_bot_rounds "$ch")
        if [[ "$rounds" -lt "$BOT_ROUND_LIMIT" ]]; then
          should_reply=true
          set_bot_rounds "$ch" $((rounds + 1))
          log "   🤖 Bot round $((rounds + 1))/${BOT_ROUND_LIMIT} in $ch"
        else
          log "   🛑 Bot round limit reached (${BOT_ROUND_LIMIT}) in $ch, ignoring"
        fi
      fi

      if [[ "$should_reply" == "true" ]]; then
        process_msg "$ch" "$msg_id" "$username" "$msgcontent" "群組"
      fi

      set_last_id "$ch" "$msg_id"
    done

    latest=$(echo "$raw" | jq -r '.[0].id // empty' 2>/dev/null || true)
    [[ -n "$latest" ]] && set_last_id "$ch" "$latest"
  done

  sleep "$POLL_INTERVAL"
done
