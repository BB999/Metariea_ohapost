#!/bin/bash

# GitHub Actions フォールバック実行スクリプト
# 毎朝7:10(JST)にGitHub Actionsの実行結果を確認し、
# 失敗または未実行の場合にローカルのohapost.shを実行する

# launchd環境ではPATHが制限されるため、Homebrewのパスを追加
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OHAPOST_SCRIPT="$SCRIPT_DIR/../ohapost.sh"

# ログ出力（タイムスタンプ付き）
log() {
  echo "[$(TZ='Asia/Tokyo' date '+%Y-%m-%d %H:%M:%S')] $1"
}

# macOS Keychainから設定を読み込み
GITHUB_REPO=$(security find-generic-password -s "ohapost" -a "github-repo" -w)
DISCORD_WEBHOOK_URL=$(security find-generic-password -s "ohapost" -a "discord-webhook-url" -w)

WORKFLOW_NAME="OneDrive to Discord"

log "===== フォールバックチェック開始 ====="
log "GITHUB_REPO: $GITHUB_REPO"

# Discordに通知を送信
notify_discord() {
  local message="$1"
  curl -s -X POST \
    -H "Content-Type: application/json" \
    -d "{\"content\": \"$message\"}" \
    "$DISCORD_WEBHOOK_URL" > /dev/null
}

# ネットワーク接続を確認
check_network() {
  curl -s --max-time 5 -o /dev/null -w "%{http_code}" "https://github.com" 2>/dev/null
}

# ネットワーク接続待ち（最大60秒）
wait_for_network() {
  local max_wait=60
  local interval=5
  local waited=0

  while [ $waited -lt $max_wait ]; do
    local http_code
    http_code=$(check_network)
    if [ "$http_code" -ge 200 ] 2>/dev/null && [ "$http_code" -lt 400 ] 2>/dev/null; then
      log "✅ ネットワーク接続OK (HTTP $http_code, ${waited}秒待機)"
      return 0
    fi
    log "⏳ ネットワーク未接続... ${waited}/${max_wait}秒 (HTTP: $http_code)"
    sleep $interval
    waited=$((waited + interval))
  done

  log "❌ ネットワーク接続タイムアウト (${max_wait}秒)"
  return 1
}

# GitHub Actionsの最新の実行結果を取得し、今日（JST）のものか確認
TODAY_JST=$(TZ='Asia/Tokyo' date +%Y-%m-%d)
WAIT_SECONDS=300  # 実行中の場合の待機時間（5分）

check_workflow_status() {
  local run_data gh_error
  gh_error=$(mktemp)
  run_data=$(gh run list \
    --repo "$GITHUB_REPO" \
    --workflow "$WORKFLOW_NAME" \
    --limit 1 \
    --json conclusion,createdAt,status \
    --jq '.[0] // empty' 2>"$gh_error")
  local exit_code=$?

  if [ $exit_code -ne 0 ]; then
    log "❌ gh run list 失敗 (exit: $exit_code): $(cat "$gh_error")"
    rm -f "$gh_error"
    echo "none"
    return
  fi
  rm -f "$gh_error"

  if [ -z "$run_data" ]; then
    log "⚠️ gh run list: データが空"
    echo "none"
    return
  fi

  local created_at status conclusion run_date_jst
  created_at=$(echo "$run_data" | jq -r '.createdAt')
  status=$(echo "$run_data" | jq -r '.status // "unknown"')
  conclusion=$(echo "$run_data" | jq -r '.conclusion // "none"')
  log "📊 ワークフロー情報: status=$status, conclusion=$conclusion, createdAt=$created_at"

  # ISO 8601形式からエポック秒に変換してJSTの日付を取得（macOS互換）
  # ミリ秒(.xxxZ)が含まれる場合があるので除去してからパース
  local cleaned_date epoch
  cleaned_date=$(echo "$created_at" | sed 's/\.[0-9]*Z$/Z/')
  epoch=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%SZ" "$cleaned_date" +%s 2>/dev/null)

  if [ -z "$epoch" ]; then
    log "❌ 日付パース失敗: $created_at"
    echo "none"
    return
  fi

  run_date_jst=$(TZ='Asia/Tokyo' date -j -r "$epoch" +%Y-%m-%d)
  log "📅 実行日(JST): $run_date_jst, 今日: $TODAY_JST"

  if [ "$run_date_jst" != "$TODAY_JST" ]; then
    log "⚠️ 今日の実行ではない ($run_date_jst != $TODAY_JST)"
    echo "none"
    return
  fi

  # まだ実行中の場合
  if [ "$status" != "completed" ]; then
    log "⏳ ワークフローはまだ実行中 (status=$status)"
    echo "in_progress"
    return
  fi

  log "✅ 判定結果: $conclusion"
  echo "$conclusion"
}

# ネットワーク接続を確認してから進む
if ! wait_for_network; then
  log "❌ ネットワーク未接続のため中断"
  notify_discord "❌ **フォールバックエラー**\nネットワーク未接続のため実行できませんでした。" 2>/dev/null
  exit 1
fi

RESULT=$(check_workflow_status)
log "📋 初回チェック結果: $RESULT"

# ワークフローが実行中の場合は5分待って再確認
if [ "$RESULT" = "in_progress" ]; then
  log "⏳ ワークフローが実行中です。${WAIT_SECONDS}秒後に再確認します..."
  sleep "$WAIT_SECONDS"
  RESULT=$(check_workflow_status)
  log "📋 再チェック結果: $RESULT"

  # 待っても実行中なら未完了として扱う
  if [ "$RESULT" = "in_progress" ]; then
    log "⚠️ 待機後もワークフローが実行中のため、未完了として扱います"
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
  log "✅ GitHub Actions成功 → フォールバック不要"
  notify_discord "✅ **GitHub Actions成功**\n$WORKFLOW_NAME が正常に完了しました。"
else
  # 失敗、キャンセル、未実行の場合
  log "⚠️ フォールバック実行開始 (理由: $STATUS_JP)"
  notify_discord "⚠️ **GitHub Actionsフォールバック実行**\n$WORKFLOW_NAME が失敗または未実行のため、ローカルで実行します。\nステータス: $STATUS_JP"

  # ohapost.shを実行
  if [ -x "$OHAPOST_SCRIPT" ]; then
    if "$OHAPOST_SCRIPT"; then
      log "✅ フォールバック実行成功"
      notify_discord "✅ **フォールバック実行成功**\nohapost.sh が正常に完了しました。"
    else
      log "❌ フォールバック実行失敗 (exit: $?)"
      notify_discord "❌ **フォールバック実行失敗**\nohapost.sh の実行に失敗しました。"
      exit 1
    fi
  else
    log "❌ ohapost.sh が見つからないか実行権限がありません: $OHAPOST_SCRIPT"
    notify_discord "❌ **エラー**: ohapost.sh が見つからないか実行権限がありません"
    exit 1
  fi
fi

log "===== フォールバックチェック完了 ====="
