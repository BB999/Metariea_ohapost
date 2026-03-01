#!/usr/bin/env python3
"""
X (Twitter) 投稿スクリプト
Usage: python3 post_x.py "ツイートテキスト" "画像パス(任意)"

v2 API対応版: メディアアップロードに /2/media/upload エンドポイントを使用
"""

import os
import sys
import json
import time
import random
import hmac
import hashlib
import base64
import mimetypes
import urllib.parse
import urllib.request

# 環境変数から認証情報を取得
API_KEY = os.environ.get('X_API_KEY')
API_SECRET = os.environ.get('X_API_SECRET')
ACCESS_TOKEN = os.environ.get('X_ACCESS_TOKEN')
ACCESS_TOKEN_SECRET = os.environ.get('X_ACCESS_TOKEN_SECRET')


def create_oauth_signature(method, url, params, api_secret, token_secret):
    """OAuth 1.0a 署名を生成"""
    sorted_params = sorted(params.items())
    param_string = '&'.join([f"{k}={v}" for k, v in sorted_params])

    signature_base = f"{method}&{urllib.parse.quote(url, safe='')}&{urllib.parse.quote(param_string, safe='')}"
    signing_key = f"{api_secret}&{token_secret}"

    signature = base64.b64encode(
        hmac.new(
            signing_key.encode(),
            signature_base.encode(),
            hashlib.sha1
        ).digest()
    ).decode()

    return urllib.parse.quote(signature, safe='')


def create_auth_header(method, url, extra_params=None):
    """OAuth 1.0a Authorization ヘッダーを生成"""
    oauth_params = {
        'oauth_consumer_key': API_KEY,
        'oauth_nonce': str(random.randint(0, 1000000000)),
        'oauth_signature_method': 'HMAC-SHA1',
        'oauth_timestamp': str(int(time.time())),
        'oauth_token': ACCESS_TOKEN,
        'oauth_version': '1.0'
    }

    # 署名用パラメータ（OAuthパラメータ + 追加パラメータ）
    sign_params = dict(oauth_params)
    if extra_params:
        sign_params.update(extra_params)

    oauth_params['oauth_signature'] = create_oauth_signature(
        method, url, sign_params, API_SECRET, ACCESS_TOKEN_SECRET
    )

    return 'OAuth ' + ', '.join([f'{k}="{v}"' for k, v in sorted(oauth_params.items())])


def upload_media(file_path):
    """v2 API でメディアアップロード (OneShot)"""

    file_size = os.path.getsize(file_path)
    mime_type = mimetypes.guess_type(file_path)[0] or 'application/octet-stream'

    print(f"📊 ファイル: {file_path} ({file_size} bytes, {mime_type})")

    upload_url = "https://api.x.com/2/media/upload"

    with open(file_path, 'rb') as f:
        file_data = f.read()

    boundary = f'----WebKitFormBoundary{random.randint(1000000000, 9999999999)}'

    # multipart/form-data ボディを構築
    body_parts = []

    # media パート
    body_parts.append(f'--{boundary}\r\n')
    body_parts.append('Content-Disposition: form-data; name="media"; filename="upload"\r\n')
    body_parts.append(f'Content-Type: {mime_type}\r\n')
    body_parts.append('\r\n')

    # media_category パート
    category_part = f'\r\n--{boundary}\r\n'
    category_part += 'Content-Disposition: form-data; name="media_category"\r\n\r\n'
    category_part += 'tweet_image'
    category_suffix = f'\r\n--{boundary}--\r\n'

    body = ''.join(body_parts).encode() + file_data + category_part.encode() + category_suffix.encode()

    auth_header = create_auth_header('POST', upload_url)

    req = urllib.request.Request(upload_url, data=body, headers={
        'Authorization': auth_header,
        'Content-Type': f'multipart/form-data; boundary={boundary}'
    })

    try:
        with urllib.request.urlopen(req) as response:
            result = json.loads(response.read().decode())
            media_id = result['data']['id']
            print(f"✅ アップロード成功: media_id={media_id}")
            return media_id
    except urllib.error.HTTPError as e:
        error_body = e.read().decode()
        print(f"❌ アップロード失敗: {e.code} - {e.reason}")
        print(f"   詳細: {error_body}")
        return None
    except Exception as e:
        print(f"❌ アップロード例外: {e}")
        return None


def post_tweet(text, image_file=None):
    """ツイート投稿"""
    url = "https://api.x.com/2/tweets"

    # メディアアップロード
    uploaded_media_ids = []
    if image_file and os.path.exists(image_file):
        print(f"📤 画像アップロード中: {image_file}")
        media_id = upload_media(image_file)
        if media_id:
            uploaded_media_ids.append(media_id)
        else:
            print(f"⚠️ 画像アップロードに失敗、テキストのみで投稿を続行")

    # リクエストボディ
    tweet_data = {'text': text}
    if uploaded_media_ids:
        tweet_data['media'] = {'media_ids': uploaded_media_ids}
        print(f"📎 メディア添付: {len(uploaded_media_ids)}個")

    body = json.dumps(tweet_data).encode('utf-8')

    auth_header = create_auth_header('POST', url)

    req = urllib.request.Request(url, data=body, headers={
        'Authorization': auth_header,
        'Content-Type': 'application/json'
    })

    try:
        with urllib.request.urlopen(req) as response:
            result = json.loads(response.read().decode())
            print(f"✅ ツイートを投稿しました: {text}")
            print(f"   ツイートID: {result['data']['id']}")
            print(f"   URL: https://x.com/i/web/status/{result['data']['id']}")
            return True
    except urllib.error.HTTPError as e:
        error_body = e.read().decode()
        print(f"❌ ツイート投稿エラー: {e.code} - {e.reason}")
        print(f"   詳細: {error_body}")
        return False


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 post_x.py \"ツイートテキスト\" [画像パス]")
        sys.exit(1)

    tweet_text = sys.argv[1]
    image_file = sys.argv[2] if len(sys.argv) > 2 else None

    if not all([API_KEY, API_SECRET, ACCESS_TOKEN, ACCESS_TOKEN_SECRET]):
        print("❌ 認証情報が不足しています")
        print("   以下の環境変数を設定してください:")
        print("   - X_API_KEY")
        print("   - X_API_SECRET")
        print("   - X_ACCESS_TOKEN")
        print("   - X_ACCESS_TOKEN_SECRET")
        sys.exit(1)

    success = post_tweet(tweet_text, image_file)
    sys.exit(0 if success else 1)


if __name__ == '__main__':
    main()
