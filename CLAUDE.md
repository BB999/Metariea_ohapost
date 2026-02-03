# プロジェクト固有のルール

## 実行環境
- このプロジェクトは **Ubuntu** で動作する
- macOS固有の機能（launchd等）は使用しない

## シェルスクリプトのルール
- 外部スクリプトを実行した後は、その実行結果（成功/失敗）を必ず通知すること
- 処理の成功・失敗に関わらず、結果をDiscordに通知すること

## 設定ファイル
- `config.env` に環境変数が定義されている
- Discord Webhook URL: `DISCORD_WEBHOOK_URL`
- GitHubリポジトリ: `GITHUB_REPO`
