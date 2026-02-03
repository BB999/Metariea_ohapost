# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## プロジェクト概要

毎朝ランダムな画像と挨拶メッセージをX（Twitter）に自動投稿するシステム。OneDriveから画像を取得し、Xに投稿して、Discordで通知する。

## 実行環境

- **本番環境**: Ubuntu（ローカル実行用）
- macOS固有の機能（launchd等）は使用しない
- GitHub Actionsでも実行される（毎日6:55 JST）

## コマンド

### ローカル実行
```bash
cd local-script
./ohapost.sh
```

### フォールバック実行（GitHub Actions失敗時の手動確認）
```bash
cd local-script/fallback
./check_and_run.sh
```

## アーキテクチャ

### 処理フロー
1. GitHubから前回の番号を取得（`previous file`）
2. OneDriveで画像を探索（循環検索）
3. ランダムに画像をダウンロード
4. ランダムな挨拶メッセージを選択
5. X（Twitter）に投稿
6. 投稿済みフォルダに画像を移動
7. GitHubの番号を更新
8. Discordに通知

### 主要ファイル
- `local-script/ohapost.sh` - メインオーケストレーション
- `local-script/post_x.py` - X投稿（OAuth 1.0a）
- `local-script/compress_image.py` - 画像圧縮（8MB超の場合）
- `local-script/fallback/check_and_run.sh` - GitHub Actionsフォールバック

### GitHub Actionsワークフロー
- `onedrive-to-discord.yml` - メインオーケストレーション
- `onedrive-downloader.yml` - 画像ダウンロード
- `x-poster.yml` - X投稿
- `onedrive-mover.yml` - 画像移動・番号更新
- `commit-pusher.yml` - Git commit＆push

## 開発ルール

### シェルスクリプト
- 外部スクリプト実行後は、成功/失敗を必ずDiscordに通知すること
- 処理の成功・失敗に関わらず、結果を通知すること

### 設定ファイル
`local-script/config.env`に環境変数を定義：
- `GITHUB_REPO` - GitHubリポジトリ
- `DISCORD_WEBHOOK_URL` - Discord Webhook URL
- `ONEDRIVE_BASE_PATH` - OneDriveのパス（rclone）
- `X_API_KEY`, `X_API_SECRET`, `X_ACCESS_TOKEN`, `X_ACCESS_TOKEN_SECRET` - X API認証

## 外部依存

- **rclone** - OneDriveアクセス
- **gh** - GitHub CLI
- **jq** - JSON処理
- **PIL/Pillow** - 画像処理（Python）
