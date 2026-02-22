#!/bin/bash
set -e

# スクリプトのディレクトリを取得
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# macOS Keychainから設定を読み込み
export GITHUB_REPO=$(security find-generic-password -s "ohapost" -a "github-repo" -w)
export DISCORD_WEBHOOK_URL=$(security find-generic-password -s "ohapost" -a "discord-webhook-url" -w)
export ONEDRIVE_BASE_PATH=$(security find-generic-password -s "ohapost" -a "onedrive-base-path" -w)
export X_API_KEY=$(security find-generic-password -s "ohapost" -a "x-api-key" -w)
export X_API_SECRET=$(security find-generic-password -s "ohapost" -a "x-api-secret" -w)
export X_ACCESS_TOKEN=$(security find-generic-password -s "ohapost" -a "x-access-token" -w)
export X_ACCESS_TOKEN_SECRET=$(security find-generic-password -s "ohapost" -a "x-access-token-secret" -w)

# 一時ディレクトリ
IMAGES_DIR="$SCRIPT_DIR/images"
mkdir -p "$IMAGES_DIR"
rm -f "$IMAGES_DIR"/*

# 挨拶メッセージリスト
GREETINGS=(
  "おはようー。"
  "おはようございます。"
  "おはよ～。"
  "おはようございます！"
  "Good morning!!"
  "おはよう。"
  "おはようございまーす。"
  "おはよ！"
  "おはよーございます。"
  "Good morning."
  "おはようー"
  "おはよ！"
  "おはようございまーす"
  "Good morning!"
)

#######################################
# GitHub から previous file を読み込む
#######################################
get_previous_number() {
  echo "📖 GitHubから前回の番号を取得中..."

  # ファイル名にスペースがあるのでURLエンコード
  local response
  response=$(gh api "repos/${GITHUB_REPO}/contents/previous%20file" 2>/dev/null)

  if [ $? -ne 0 ]; then
    echo "❌ GitHubからの読み込みに失敗しました"
    exit 1
  fi

  PREV_NUM=$(echo "$response" | jq -r '.content' | base64 -D | tr -d '\n')
  FILE_SHA=$(echo "$response" | jq -r '.sha')

  echo "✅ 前回の番号: $PREV_NUM"
}

#######################################
# GitHub の previous file を更新
#######################################
update_previous_number() {
  local new_number="$1"
  local date_str
  date_str=$(TZ='Asia/Tokyo' date +%Y-%m-%d)

  echo "📝 GitHubの番号を更新中... ($new_number)"

  local content
  content=$(echo -n "$new_number" | base64)

  gh api "repos/${GITHUB_REPO}/contents/previous%20file" \
    -X PUT \
    -f message="[$date_str] Update previous number to $new_number" \
    -f content="$content" \
    -f sha="$FILE_SHA" > /dev/null

  if [ $? -eq 0 ]; then
    echo "✅ GitHub更新完了"
  else
    echo "❌ GitHub更新失敗"
    exit 1
  fi
}

#######################################
# 画像があるフォルダを探す
#######################################
find_folder_with_images() {
  echo "🔍 画像があるフォルダを探索中..."

  # フォルダ一覧を取得（番号付きフォルダのみ）
  local folders
  folders=$(rclone lsd "$ONEDRIVE_BASE_PATH" | awk '{print $NF}' | grep "^[0-9]" | sort)
  local max_num
  max_num=$(echo "$folders" | wc -l | tr -d ' ')

  if [ "$max_num" -eq 0 ]; then
    echo "❌ 番号付きフォルダが見つかりません"
    exit 1
  fi

  echo "📁 フォルダ数: $max_num"

  local checked=0
  local current_num=$PREV_NUM
  local start_num=$((PREV_NUM + 1))

  if [ $start_num -gt $max_num ]; then
    start_num=1
  fi

  while [ $checked -lt $max_num ]; do
    current_num=$((current_num + 1))
    if [ $current_num -gt $max_num ]; then
      current_num=1
      echo "🔄 最大数を超えたので1に戻る"
    fi

    # 一周したかチェック
    if [ $checked -gt 0 ] && [ $current_num -eq $start_num ]; then
      echo "❌ 全フォルダをチェックしたが画像が見つからない"
      exit 1
    fi

    echo "🔍 フォルダ番号 $current_num をチェック中..."

    # 番号を2桁にゼロパディング
    local num_padded
    num_padded=$(printf "%02d" $current_num)
    local folder
    folder=$(echo "$folders" | grep "^${num_padded}" | head -n 1)

    if [ -z "$folder" ]; then
      echo "⚠️ フォルダ $current_num が見つからない、スキップ..."
      checked=$((checked + 1))
      continue
    fi

    echo "📁 フォルダ: $folder"

    # 投稿前フォルダに画像があるか確認
    local source_path="${ONEDRIVE_BASE_PATH}${folder}/投稿前/"
    local image_count
    image_count=$(rclone ls "$source_path" 2>/dev/null | awk '{print $2}' | grep -iE '\.(jpg|jpeg|png|gif|webp)$' | wc -l | tr -d ' ')

    if [ "$image_count" -gt 0 ]; then
      echo "✅ $folder/投稿前/ に ${image_count} 枚の画像を発見"
      FOUND_FOLDER="$folder"
      FOUND_NUMBER=$current_num
      SOURCE_PATH="$source_path"
      return 0
    else
      echo "⚠️ $folder/投稿前/ に画像なし、スキップ..."
    fi

    checked=$((checked + 1))
  done

  echo "❌ 画像が見つかりませんでした"
  exit 1
}

#######################################
# ランダムに画像を選択してダウンロード
#######################################
download_random_image() {
  echo "📥 画像をダウンロード中..."

  # 画像一覧を取得してランダムに選択
  local images
  images=$(rclone ls "$SOURCE_PATH" | awk '{print $2}' | grep -iE '\.(jpg|jpeg|png|gif|webp)$')
  local image_count
  image_count=$(echo "$images" | wc -l | tr -d ' ')
  local random_index=$((RANDOM % image_count + 1))
  local image
  image=$(echo "$images" | sed -n "${random_index}p")

  if [ -z "$image" ]; then
    echo "❌ 画像が見つかりません"
    exit 1
  fi

  echo "📷 選択した画像: $image"

  # ダウンロード
  rclone copy "${SOURCE_PATH}${image}" "$IMAGES_DIR/"

  SELECTED_IMAGE="$image"
  IMAGE_PATH="$IMAGES_DIR/$image"

  echo "✅ ダウンロード完了: $IMAGE_PATH"
  ls -la "$IMAGE_PATH"
}

#######################################
# ランダムな挨拶メッセージを選択
#######################################
select_greeting() {
  local index=$((RANDOM % ${#GREETINGS[@]}))
  GREETING_MESSAGE="${GREETINGS[$index]}"
  echo "💬 挨拶メッセージ: $GREETING_MESSAGE"
}

#######################################
# X (Twitter) に投稿
#######################################
post_to_x() {
  echo "🐦 Xに投稿中..."

  python3 "$SCRIPT_DIR/post_x.py" "$GREETING_MESSAGE" "$IMAGE_PATH"

  if [ $? -eq 0 ]; then
    echo "✅ X投稿完了"
  else
    echo "❌ X投稿失敗"
    exit 1
  fi
}

#######################################
# 画像を投稿済みフォルダに移動
#######################################
move_image() {
  echo "📦 画像を投稿済みフォルダに移動中..."

  local date_str
  date_str=$(TZ='Asia/Tokyo' date +%Y-%m-%d)

  # 投稿前から投稿済みへ
  local base_path
  base_path=$(echo "$SOURCE_PATH" | sed 's|投稿前/$||')
  local dest="${base_path}投稿済み/${date_str}_${SELECTED_IMAGE}"
  local source="${SOURCE_PATH}${SELECTED_IMAGE}"

  echo "  From: $source"
  echo "  To: $dest"

  rclone copyto "$source" "$dest"
  rclone delete "$source"

  echo "✅ 画像移動完了"
}

#######################################
# Discordに通知
#######################################
notify_discord() {
  local status="$1"
  local message="$2"

  echo "💬 Discordに通知中..."

  local payload
  payload=$(jq -n --arg content "$message" '{content: $content}')

  curl -s -X POST \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "$DISCORD_WEBHOOK_URL" > /dev/null

  echo "✅ Discord通知完了"
}

#######################################
# Discordに画像を送信
#######################################
send_image_to_discord() {
  echo "📷 Discordに画像を送信中..."

  local file_size
  file_size=$(stat -f%z "$IMAGE_PATH" 2>/dev/null || stat -c%s "$IMAGE_PATH" 2>/dev/null)

  # 8MB超の場合は圧縮
  if [ "$file_size" -gt 8388608 ]; then
    echo "⚠️ ファイルが8MBを超えているため圧縮します"
    local compressed="$IMAGES_DIR/compressed.jpg"
    python3 "$SCRIPT_DIR/compress_image.py" "$IMAGE_PATH" "$compressed" 1920 85
    IMAGE_PATH="$compressed"
  fi

  curl -s -X POST \
    -F "file=@$IMAGE_PATH" \
    "$DISCORD_WEBHOOK_URL" > /dev/null

  echo "✅ Discord画像送信完了"
}

#######################################
# ローカルの一時画像を削除
#######################################
cleanup_images() {
  echo "🧹 一時画像を削除中..."
  rm -f "$IMAGES_DIR"/*
  echo "✅ 削除完了"
}

#######################################
# メイン処理
#######################################
main() {
  echo "========================================"
  echo "🌅 おはツイ投稿スクリプト"
  echo "========================================"
  echo ""

  # 1. GitHubから前回の番号を取得
  get_previous_number

  # 2. 画像があるフォルダを探す
  find_folder_with_images

  # 3. ランダムに画像をダウンロード
  download_random_image

  # 4. 挨拶メッセージを選択
  select_greeting

  # 5. Xに投稿
  post_to_x

  # 6. 画像を投稿済みに移動
  move_image

  # 7. GitHubの番号を更新
  update_previous_number "$FOUND_NUMBER"

  # 8. Discordに通知
  notify_discord "success" "$GREETING_MESSAGE"
  send_image_to_discord

  local report="✅ **処理完了レポート**

📥 ダウンロード: 成功
🐦 X投稿: 成功
📁 画像移動: 成功
🔢 番号更新: 成功 ($FOUND_NUMBER)
💬 Discord送信: 成功"

  notify_discord "success" "$report"

  # 9. ローカルの一時画像を削除
  cleanup_images

  echo ""
  echo "========================================"
  echo "🎉 すべての処理が完了しました"
  echo "========================================"
}

# エラーハンドリング
trap 'echo "❌ エラーが発生しました"; notify_discord "error" "❌ おはツイ投稿でエラーが発生しました"; exit 1' ERR

# 実行
main
