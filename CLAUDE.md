# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## プロジェクト概要

毎朝ランダムな画像と挨拶メッセージをX（Twitter）に自動投稿するシステム。OneDriveから画像を取得し、Xに投稿して、Discordで通知する。

## 実行環境

**本番は GitHub Actions のみ。常時稼働のマシンは無い。**

起動指示は Cloudflare Worker（`worker/`）の Cron Trigger が出す。毎朝 UTC 22:00（= JST 7:00）に
`onedrive-to-discord.yml` を `workflow_dispatch` で叩き、実処理は GitHub Actions が行う。

GitHub の `on: schedule` は使わない。キュー登録そのものが数時間遅れることがあり
（2026-08 に最大 +7時間59分 を実測。全 run は `success` のまま朝の投稿だけが昼過ぎにずれた）、
2026-08-29 に定時性だけ Cloudflare へ移した。**時刻が意味を持つ処理を `on: schedule` に戻さないこと。**

`local-script/` は現在使っていない。かつて Ubuntu / macOS のローカル実行と GitHub Actions の
フォールバックを担っていたが、そのマシンごと運用から外れた。`local-script/fallback/check_and_run.sh`
は macOS Keychain 前提のまま止まっており、動作しない。参考資料として残しているだけ。

## コマンド

### Worker のデプロイ
```bash
cd /Users/noranekobi/coding/Metariea_ohapost/worker && npx wrangler deploy
```
`wrangler` は必ずディレクトリを明示して打つ。設定ファイルの無い場所で `deploy` すると、
別の Worker を推測で作って公開してしまう。

### 手動実行（Cloudflare を待たずに投稿する）
```bash
gh workflow run onedrive-to-discord.yml
```
X投稿を伴わない確認は `-f debug=true` を付ける。

### Worker のログ確認
```bash
cd /Users/noranekobi/coding/Metariea_ohapost/worker && npx wrangler tail
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
- `worker/src/index.js` - 起動指示専用の Cloudflare Worker（cronで `workflow_dispatch` を叩くだけ）
- `worker/wrangler.jsonc` - Worker設定。cron式はUTC固定（TZ指定は不可）
- `previous file` - 前回の画像番号。ワークフローが更新してcommitする

以下は現在未使用（上記「実行環境」参照）:
- `local-script/ohapost.sh` - かつてのローカル版オーケストレーション
- `local-script/post_x.py` - X投稿（OAuth 1.0a）
- `local-script/compress_image.py` - 画像圧縮（8MB超の場合）
- `local-script/fallback/check_and_run.sh` - macOS Keychain前提のまま停止中

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

### Worker のシークレット
`npx wrangler secret put <名前>` で登録する。**TTYの無いシェルから打つと空文字を登録して
`Success` と表示する**ので、値はパイプで渡し、`wrangler tail` のログで長さを確認すること。

- `GITHUB_TOKEN` - Fine-grained PAT。対象は本リポジトリのみ、権限は `Actions: Read and write` だけ。
  **期限切れで静かに死ぬ**ので、失効前に入れ替える。失敗時は Worker が Discord に通知する
- `DISCORD_WEBHOOK_URL` - 起動指示が失敗したときの通知先

### 設定ファイル（未使用のローカル版）
`local-script/config.env`に環境変数を定義：
- `GITHUB_REPO` - GitHubリポジトリ
- `DISCORD_WEBHOOK_URL` - Discord Webhook URL
- `ONEDRIVE_BASE_PATH` - OneDriveのパス（rclone）
- `X_API_KEY`, `X_API_SECRET`, `X_ACCESS_TOKEN`, `X_ACCESS_TOKEN_SECRET` - X API認証

## 外部依存

- **wrangler** - Cloudflare Worker のデプロイ（`npx wrangler`。グローバル導入はしていない）
- **rclone** - OneDriveアクセス
- **gh** - GitHub CLI
- **jq** - JSON処理
- **PIL/Pillow** - 画像処理（Python）
