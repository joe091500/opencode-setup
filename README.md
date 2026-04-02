# OpenCode 完整調教配置

OpenCode AI 程式開發助手的完整配置檔，包含自訂 agents、Discord bridge、TUI 設定、系統指令，以及 216 個 skill commands。

基於 [OpenCode](https://github.com/nicepkg/opencode) TUI，搭配本機 SGLang 運行 Qwen3.5 122B 模型，完全免費。

## 包含內容

### Agents（6 個專業角色）

| Agent | 用途 | 模式 |
|-------|------|------|
| **Coder** | 主力開發：寫程式、修 bug、改檔案 | primary |
| **Architect** | 架構設計：系統規劃、技術決策（不寫程式） | primary（唯讀） |
| **Debugger** | 系統除錯：追蹤根因、驗證假說 | primary |
| **Reviewer** | 程式碼審查：安全性、完整性、風格 | subagent（唯讀） |
| **OpenClaw** | OpenClaw 基礎設施管理：gateway、cron、模型 | primary |
| **Researcher** | 程式碼探索：追蹤執行流程、找檔案、理解架構 | subagent（唯讀） |

### Discord Bridge

- `discord-bridge.sh` — Discord 雙向橋接腳本 v7
  - DM 頻道：owner 所有訊息直接轉發
  - 群組頻道：@bot 或 @everyone 時回覆
  - Bot 互動：其他 bot @本 bot 時回覆，10 輪上限防無限循環
  - TUI 同步：透過 `/tui/append-prompt` + `/tui/submit-prompt` 注入 OpenCode

### 系統指令

- `instructions.md` — 完整系統指令
  - 身份定義（OpenCode，不是其他 AI 助手）
  - 團隊關係圖
  - 深度思考指引
  - 核心開發原則（讀後寫、最小改動、完整清理、安全優先）
  - OpenClaw 基礎設施知識
  - 工作流程規則

### 設定檔

- `config/opencode.json` — OpenCode 主設定
  - 4 個 SGLang provider（122B Clawhead / 122B B300 / 35B Mini / 27B Reasoning）
  - 8 個 agent 溫度與步數設定
  - Discord MCP 整合
- `config/tui.json` — TUI 介面設定
  - 快捷鍵綁定（Ctrl+X D/R/A/O 切換 agent）

### Skill Commands

`~/.opencode/command/` 目錄下有 216 個 skill commands（未包含在此 repo 中，需另外安裝）。

## 安裝方式

### 1. 安裝前置需求

```bash
# OpenCode TUI
npm install -g opencode

# 其他工具
brew install bun jq curl
```

### 2. 複製配置檔

```bash
# 複製到 ~/.opencode/
cp instructions.md ~/.opencode/
cp ocd ~/.opencode/
chmod +x ~/.opencode/ocd
cp discord-bridge.sh ~/.opencode/
chmod +x ~/.opencode/discord-bridge.sh
mkdir -p ~/.opencode/agent
cp agent/*.md ~/.opencode/agent/

# 複製到 ~/.config/opencode/
mkdir -p ~/.config/opencode
cp config/opencode.json ~/.config/opencode/
cp config/tui.json ~/.config/opencode/
```

### 3. 設定 Discord Bot Token

編輯以下兩個檔案，將 `YOUR_DISCORD_BOT_TOKEN_HERE` 替換為你的 Discord bot token：

- `~/.opencode/discord-bridge.sh` 第 8 行 `TOKEN=`
- `~/.config/opencode/opencode.json` 中 `DISCORD_BOT_TOKEN` 欄位

### 4. 設定模型 endpoint

編輯 `~/.config/opencode/opencode.json`，將 `baseURL` 改為你自己的 SGLang / vLLM / OpenAI-compatible 伺服器位址。

## 使用方式

### `ocd` 啟動器

```bash
# 加入 PATH（建議放 /usr/local/bin 或 ~/.local/bin）
ln -s ~/.opencode/ocd /usr/local/bin/ocd

# 啟動 OpenCode + Discord bridge
ocd

# 帶額外參數啟動
ocd --some-flag
```

`ocd` 做的事：
1. 殺掉舊的 discord-bridge 程序
2. 在背景啟動 OpenCode TUI（port 4096）
3. 等待 TUI server 啟動完成
4. 自動啟動 Discord bridge

### TUI 快捷鍵

| 快捷鍵 | 切換到 |
|--------|--------|
| `Ctrl+X D` | Debugger agent |
| `Ctrl+X R` | Reviewer agent |
| `Ctrl+X A` | Architect agent |
| `Ctrl+X O` | OpenClaw agent |

## Discord Bridge 架構

```
Discord 用戶
    │
    ▼
Discord API（polling，5 秒一次）
    │
    ▼
discord-bridge.sh
    ├── 判斷是否回覆（DM / @bot / @everyone / bot互動）
    ├── 注入 OpenCode TUI（/tui/append-prompt + /tui/submit-prompt）
    ├── 直接呼叫 SGLang API 取得回覆
    └── 發送回覆到 Discord
```

訊息流程：
1. Bridge 每 5 秒 polling Discord API 取得新訊息
2. 依照頻道類型和 mention 規則判斷是否回覆
3. 同時注入 OpenCode TUI（讓終端機看到對話）
4. 直接呼叫本機 SGLang API 產生回覆（跳過 OpenCode 中間層）
5. 回覆發送到 Discord（群組用 quote reply，DM 不用）

## 前置需求

| 工具 | 用途 |
|------|------|
| [OpenCode](https://github.com/nicepkg/opencode) | AI coding TUI |
| [bun](https://bun.sh) | Discord MCP server 運行環境 |
| [jq](https://jqlang.github.io/jq/) | JSON 處理 |
| [curl](https://curl.se) | HTTP 請求 |
| SGLang / vLLM / OpenAI-compatible server | 模型推理後端 |

## 注意事項

- `opencode.json` 中的 `baseURL` 指向本機 SGLang 伺服器，需要自行替換
- `discord-bridge.sh` 中的 `BOT_ID`、`OWNER_ID`、頻道 ID 需要換成你自己的
- Agent 的 `mode: subagent` 表示唯讀（不能 edit/write），只做分析
- `command/` 目錄（216 個 skill commands）未包含在此 repo，需要從 gstack 或其他來源安裝

## License

MIT
