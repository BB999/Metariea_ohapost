#!/bin/bash

# GitHub Actions フォールバック実行スクリプト
# 毎朝7:10(JST)にGitHub Actionsの実行結果を確認し、
# 失敗または未実行の場合にローカルのohapost.shを実行する

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OHAPOST_SCRIPT="$SCRIPT_DIR/../ohapost.sh"

# config.envからDiscord Webhook URLを読み込む
if [ -f "$SCRIPT_DIR/../config.env" ]; then
  source "$SCRIPT_DIR/../config.env"
else
  echo "config.env が見つかりません"
  exit 1
fi

WORKFLOW_NAME="OneDrive to Discord"

# Discordに通知を送信
notify_discord() {
  local message="$1"
  curl -s -X POST \
    -H "Content-Type: application/json" \
    -d "{\"content\": \"$message\"}" \
    "$DISCORD_WEBHOOK_URL" > /dev/null
}

# 今日の日付（JST）を取得
TODAY=$(TZ='Asia/Tokyo' date +%Y-%m-%d)

# GitHub Actionsの今日の実行結果を取得
RESULT=$(gh run list \
  --repo "$GITHUB_REPO" \
  --workflow "$WORKFLOW_NAME" \
  --created "$TODAY" \
  --json status,conclusion,createdAt \
  --jq '.[0].conclusion // "none"' 2>/dev/null)

if [ "$RESULT" = "success" ]; then
  # 成功の場合
  notify_discord "✅ **GitHub Actions成功**\n$WORKFLOW_NAME が正常に完了しました。"
else
  # 失敗、キャンセル、未実行の場合
  notify_discord "⚠️ **GitHub Actionsフォールバック実行**\n$WORKFLOW_NAME が失敗または未実行のため、ローカルで実行します。\nステータス: $RESULT"

  # ohapost.shを実行
  if [ -x "$OHAPOST_SCRIPT" ]; then
    "$OHAPOST_SCRIPT"
  else
    notify_discord "❌ **エラー**: ohapost.sh が見つからないか実行権限がありません"
    exit 1
  fi
fi
