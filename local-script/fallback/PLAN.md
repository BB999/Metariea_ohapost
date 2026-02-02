# GitHub Actions フォールバック実行システム（Ubuntu版）

## 概要
毎朝7:10に「OneDrive to Discord」ワークフローの実行結果を確認し、失敗または未実行の場合にローカルの `ohapost.sh` を自動実行するシステム。

## 前提条件
- GitHub Actions「OneDrive to Discord」は毎朝6:55（JST）に実行される
- フォールバック確認は7:10（JST）に実行（15分の余裕）
- 成功以外（failure, cancelled, 未実行）の場合にローカル実行

## 実装内容

### 1. 新規ファイル
```
local-script/fallback/
└── check_and_run.sh    # メインのチェック＆実行スクリプト
```

### 2. check_and_run.sh の処理フロー
1. `gh run list` で今日の「OneDrive to Discord」ワークフローを取得
2. 今日（JST）の実行があるか確認
3. 結果が「success」以外の場合：
   - Discordに「GitHub Actionsが失敗したためローカルで実行します」と通知
   - `ohapost.sh` を実行
4. 結果が「success」の場合：
   - Discordに「GitHub Actionsが成功しました」と通知

### 3. cron設定（Ubuntu）
```bash
# crontab -e で追加
10 7 * * * /path/to/local-script/fallback/check_and_run.sh
```
※ 時間はすべて日本時間（JST）

### 4. セットアップ手順
```bash
chmod +x local-script/fallback/check_and_run.sh
crontab -e
# 上記のcron行を追加
```

## 対象ファイル
- 新規作成: `local-script/fallback/check_and_run.sh`
