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

# GitHub Actionsの最新の実行結果を取得し、今日（JST）のものか確認
TODAY_JST=$(TZ='Asia/Tokyo' date +%Y-%m-%d)

RUN_DATA=$(gh run list \
  --repo "$GITHUB_REPO" \
  --workflow "$WORKFLOW_NAME" \
  --limit 1 \
  --json conclusion,createdAt \
  --jq '.[0] // empty' 2>/dev/null)

if [ -z "$RUN_DATA" ]; then
  RESULT="none"
else
  CREATED_AT=$(echo "$RUN_DATA" | jq -r '.createdAt')
  CONCLUSION=$(echo "$RUN_DATA" | jq -r '.conclusion // "none"')
  # createdAt(UTC)をJSTに変換して日付を取得
  RUN_DATE_JST=$(TZ='Asia/Tokyo' date -d "$CREATED_AT" +%Y-%m-%d)

  if [ "$RUN_DATE_JST" = "$TODAY_JST" ]; then
    RESULT="$CONCLUSION"
  else
    RESULT="none"
  fi
fi

# ステータスを日本語に変換
status_to_japanese() {
  case "$1" in
    success)   echo "成功" ;;
    failure)   echo "失敗" ;;
    cancelled) echo "キャンセル" ;;
    none)      echo "未実行" ;;
    *)         echo "$1" ;;
  esac
}

STATUS_JP=$(status_to_japanese "$RESULT")

if [ "$RESULT" = "success" ]; then
  # 成功の場合
  notify_discord "✅ **GitHub Actions成功**\n$WORKFLOW_NAME が正常に完了しました。"
else
  # 失敗、キャンセル、未実行の場合
  notify_discord "⚠️ **GitHub Actionsフォールバック実行**\n$WORKFLOW_NAME が失敗または未実行のため、ローカルで実行します。\nステータス: $STATUS_JP"

  # ohapost.shを実行
  if [ -x "$OHAPOST_SCRIPT" ]; then
    if "$OHAPOST_SCRIPT"; then
      notify_discord "✅ **フォールバック実行成功**\nohapost.sh が正常に完了しました。"
    else
      notify_discord "❌ **フォールバック実行失敗**\nohapost.sh の実行に失敗しました。"
      exit 1
    fi
  else
    notify_discord "❌ **エラー**: ohapost.sh が見つからないか実行権限がありません"
    exit 1
  fi
fi
