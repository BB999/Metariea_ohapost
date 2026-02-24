#!/bin/bash

# GitHub Actions フォールバック実行スクリプト
# 毎朝7:10(JST)にGitHub Actionsの実行結果を確認し、
# 失敗または未実行の場合にローカルのohapost.shを実行する

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OHAPOST_SCRIPT="$SCRIPT_DIR/../ohapost.sh"

# macOS Keychainから設定を読み込み
GITHUB_REPO=$(security find-generic-password -s "ohapost" -a "github-repo" -w)
DISCORD_WEBHOOK_URL=$(security find-generic-password -s "ohapost" -a "discord-webhook-url" -w)

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
WAIT_SECONDS=300  # 実行中の場合の待機時間（5分）

check_workflow_status() {
  local run_data
  run_data=$(gh run list \
    --repo "$GITHUB_REPO" \
    --workflow "$WORKFLOW_NAME" \
    --limit 1 \
    --json conclusion,createdAt,status \
    --jq '.[0] // empty' 2>/dev/null)

  if [ -z "$run_data" ]; then
    echo "none"
    return
  fi

  local created_at status conclusion run_date_jst
  created_at=$(echo "$run_data" | jq -r '.createdAt')
  status=$(echo "$run_data" | jq -r '.status // "unknown"')
  conclusion=$(echo "$run_data" | jq -r '.conclusion // "none"')
  # ISO 8601形式からエポック秒に変換してJSTの日付を取得（macOS互換）
  # ミリ秒(.xxxZ)が含まれる場合があるので除去してからパース
  local cleaned_date epoch
  cleaned_date=$(echo "$created_at" | sed 's/\.[0-9]*Z$/Z/')
  epoch=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%SZ" "$cleaned_date" +%s 2>/dev/null)

  if [ -z "$epoch" ]; then
    echo "none"
    return
  fi

  run_date_jst=$(TZ='Asia/Tokyo' date -j -r "$epoch" +%Y-%m-%d)

  if [ "$run_date_jst" != "$TODAY_JST" ]; then
    echo "none"
    return
  fi

  # まだ実行中の場合
  if [ "$status" != "completed" ]; then
    echo "in_progress"
    return
  fi

  echo "$conclusion"
}

RESULT=$(check_workflow_status)

# ワークフローが実行中の場合は5分待って再確認
if [ "$RESULT" = "in_progress" ]; then
  echo "⏳ ワークフローが実行中です。${WAIT_SECONDS}秒後に再確認します..."
  sleep "$WAIT_SECONDS"
  RESULT=$(check_workflow_status)

  # 待っても実行中なら未完了として扱う
  if [ "$RESULT" = "in_progress" ]; then
    echo "⚠️ 待機後もワークフローが実行中のため、未完了として扱います"
    RESULT="none"
  fi
fi

# ステータスを日本語に変換
status_to_japanese() {
  case "$1" in
    success)     echo "成功" ;;
    failure)     echo "失敗" ;;
    cancelled)   echo "キャンセル" ;;
    in_progress) echo "実行中" ;;
    none)        echo "未実行" ;;
    *)           echo "$1" ;;
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
