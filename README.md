# Anyrouter Keepalive

对 Anyrouter API 中转站的多账号执行健康检查（保活）与恢复监控，通过 GitHub Actions 运行，让账号在调度队列中保持活跃状态，在使用时获得更高优先级。

## 工作流一览

| 工作流 | 触发方式 | 用途 |
|---|---|---|
| **Keepalive** (`keepalive.yml`) | 定时 + 手动 | 每日凌晨自动保活，每 50 分钟轮询一轮 |
| **Keepalive Once** (`keepalive-once.yml`) | 手动 | 单次快速测活（只跑一轮） |
| **Recovery Monitor** (`monitor-recovery.yml`) | 手动 | 每 30 分钟轮询，发现恢复立刻通知，全通且响应 <30s 自动退出 |

## 工作原理

Anyrouter 的调度策略疑似为**账号级先来先用**。如果账号长时间没有请求，可能在队列中失去优先级。本项目通过定时发起轻量 API 调用让账号保持活跃。

### Keepalive（保活）

- 每天 **UTC 18:00（北京时间 02:00）** 启动一个 GitHub Actions 容器
- 容器内部每 **50 分钟** 轮询一遍所有 token（避免 6 小时限制）
- 每个 token 发送一条随机的真实工程提问，使用 `codex exec` 模式
- 通过 `~/.codex/config.toml` 将 Codex 指向 Anyrouter 的 OpenAI 兼容端点，token 经 `ANYROUTER_TOKEN` 环境变量传入（不落盘）
- 在接近 6 小时限制时自动发送汇总报告邮件
- 可选通过 QQ 邮箱接收最终报告

### Recovery Monitor（恢复监控）

- **手动触发**，启动一个 6 小时容器，每 **30 分钟** 轮询所有 token
- 每轮结束后发送**汇总邮件**（北京时间），列出每个 token 的状态和响应时间
- **早期退出**：当全部 token 正常且最大响应时间 < 30 秒时，发「快用！状态超好」邮件并自动终止
- 适合等待 Anyrouter 从不可用状态恢复的场景

## 快速开始

### 1. Fork 仓库

Fork 本仓库到你的 GitHub 账号下。

### 2. 配置 Secrets

在仓库的 **Settings → Secrets and variables → Actions** 中添加：

| Secret 名称 | 说明 | 是否必需 |
|---|---|---|
| `ANYROUTER_TOKENS` | 你的 Anyrouter API key（OpenAI 兼容格式），每行一个 | ✅ 必需 |
| `QQ_EMAIL` | QQ 邮箱地址，用于接收报告 | ❌ 可选 |
| `QQ_SMTP_AUTH_CODE` | QQ 邮箱 SMTP 授权码 | ❌ 可选 |

**ANYROUTER_TOKENS 格式：**
```
sk-xxx111
sk-xxx222
sk-xxx333
```

### 3. 启用 Actions

进入 **Actions** 页面，点击 **"I understand my workflows, go ahead and enable them"**。

| 工作流 | 手动触发路径 |
|---|---|
| 保活（定时） | Actions → Anyrouter Keepalive → Run workflow |
| 保活（单次） | Actions → Anyrouter Keepalive (Once) → Run workflow |
| 恢复监控 | Actions → Anyrouter Recovery Monitor → Run workflow |

**恢复监控**在手动触发时可自定义 `base_url` 和 `model`，默认使用 `gpt-6-astra` + `https://anyrouter.top/v1` 端点。

## 本地运行

本地运行需先安装 Codex CLI：`npm install -g @openai/codex`。

### 本地单次测试

```bash
# 设置 token
export ANYROUTER_TOKENS="sk-your-token-here"

# 运行单 token 测活
bash scripts/keepalive.sh "$ANYROUTER_TOKENS"
```

### 本地批量运行

```bash
# 方式 1：使用环境变量
export ANYROUTER_TOKENS="sk-xxx111
sk-xxx222"
export QQ_EMAIL="yourname@qq.com"
export QQ_SMTP_AUTH_CODE="your_auth_code"
bash scripts/run-all.sh

# 方式 2：使用 .env 文件
cp .env.example .env
# 编辑 .env 填入你的配置
bash scripts/run-all.sh
```

### 本地恢复监控

```bash
# 每 30 分钟轮询，全通且响应 <30s 自动退出
export ANYROUTER_TOKENS="sk-xxx111
sk-xxx222"
export QQ_EMAIL="yourname@qq.com"
export QQ_SMTP_AUTH_CODE="your_auth_code"
bash scripts/monitor-recovery.sh

# 调整轮询间隔和运行时长
POLL_INTERVAL=600 MAX_DURATION_SEC=3600 bash scripts/monitor-recovery.sh
```

### 本地单次快速测试（跳过 50 分钟等待）

```bash
export ANYROUTER_TOKENS="sk-test"
MAX_DURATION_SEC=60 bash scripts/run-all.sh
```

## 运行测试

```bash
# 安装 bats（如果未安装）
npm install -g bats

# 运行测试
bats tests/
```

## 运行时序

### Keepalive

| 时区 | 启动时间 |
|---|---|
| UTC | 18:00 |
| 北京时间 (UTC+8) | 02:00 |

容器启动后内部每 50 分钟轮询一轮，约运行 5 小时 58 分钟后自动退出（配合 GitHub Actions 的 6 小时超时限制）。

### Recovery Monitor

手动触发后每 **30 分钟** 轮询一轮。当全部 token 正常且最大响应时间 < 30 秒时自动提前退出。否则持续运行至 6 小时超时。

## 文件结构

```
├── .github/workflows/
│   ├── keepalive.yml              # 保活工作流（定时 + 手动）
│   ├── keepalive-once.yml         # 单次测活工作流（手动）
│   └── monitor-recovery.yml       # 恢复监控工作流（手动）
├── scripts/
│   ├── keepalive.sh               # 核心脚本：单 token 测活（Codex CLI）
│   ├── run-all.sh                 # 批量运行器：50 分钟轮询
│   ├── monitor-recovery.sh        # 恢复监控：30 分钟轮询 + 早期退出
│   └── prompts.txt                # prompt 池（30 条工程 + 30 条轻量）
├── tests/
│   └── test_keepalive.bats        # BATS 测试套件
├── .env.example                   # 本地配置模板
└── README.md
```

## 注意事项

- **不要滥用**：保活仅凌晨低峰期运行，恢复监控按需手动触发，频率合理不会对 Anyrouter 造成压力
- **遵守条款**：请遵守 Anyrouter 的使用条款和服务协议
- **频率控制**：token 之间间隔 30 秒（带随机抖动），避免触发限流
- **成本**：每次测活使用 `gpt-6-astra` 模型，通过 `https://anyrouter.top/v1` 端点直连，单次成本极低
- **API 协议**：默认使用 Codex 原生 `responses` 协议；若 Anyrouter 端点仅支持 Chat Completions，请设置环境变量 `WIRE_API=chat`
- **邮箱配置**：QQ 邮箱的 SMTP 授权码请在 QQ 邮箱 → 设置 → 账号 → POP3/IMAP/SMTP 服务 中生成
- **Prompt 池**：共 60 条 prompt（30 条工程提问 + 30 条轻量级快速问答），每次随机选取一条发送
