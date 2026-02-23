#!/bin/bash
# Twitter posting library

# Get credentials based on TWITTER_ACCOUNT env var
get_twitter_credentials() {
  source /home/phan_harry/.openclaw/.env
  
  if [ "$TWITTER_ACCOUNT" = "oxdasx" ]; then
    export X_CONSUMER_KEY="$OXDASX_API_KEY"
    export X_CONSUMER_SECRET="$OXDASX_API_KEY_SECRET"
    export X_ACCESS_TOKEN="$OXDASX_ACCESS_TOKEN"
    export X_ACCESS_TOKEN_SECRET="$OXDASX_ACCESS_TOKEN_SECRET"
    export X_USERNAME="0xdasx"
  else
    # Default to mr_crtee
    export X_CONSUMER_KEY="${X_CONSUMER_KEY}"
    export X_CONSUMER_SECRET="${X_CONSUMER_SECRET}"
    export X_ACCESS_TOKEN="${X_ACCESS_TOKEN}"
    export X_ACCESS_TOKEN_SECRET="${X_ACCESS_TOKEN_SECRET}"
    export X_USERNAME="${X_USERNAME:-mr_crtee}"
  fi
}

# Post text-only to Twitter
twitter_post_text() {
  local text="$1"
  local reply_to_id="$2"
  local quote_tweet_id="$3"
  
  get_twitter_credentials
  
  # Consolidated posting logic - always use safe Python with sys.argv
  python3 - "$text" "${reply_to_id:-}" "${quote_tweet_id:-}" <<'EOF'
import requests
from requests_oauthlib import OAuth1
import os
import sys
import json

text = sys.argv[1]
reply_to = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] else None
quote_id = sys.argv[3] if len(sys.argv) > 3 and sys.argv[3] else None

consumer_key = os.environ['X_CONSUMER_KEY']
consumer_secret = os.environ['X_CONSUMER_SECRET']
access_token = os.environ['X_ACCESS_TOKEN']
access_token_secret = os.environ['X_ACCESS_TOKEN_SECRET']

auth = OAuth1(consumer_key, consumer_secret, access_token, access_token_secret)

url = "https://api.twitter.com/2/tweets"
payload = {"text": text}

if reply_to:
    payload["reply"] = {"in_reply_to_tweet_id": reply_to}

if quote_id:
    payload["quote_tweet_id"] = quote_id

response = requests.post(url, auth=auth, json=payload)

if response.status_code == 201:
    tweet = response.json()
    tweet_id = tweet['data']['id']
    if reply_to:
        # Thread mode: just print ID for chaining
        print(tweet_id)
    else:
        print(f"✓ Tweet posted successfully!")
        print(f"Tweet ID: {tweet_id}")
        print(f"URL: https://twitter.com/user/status/{tweet_id}")
else:
    print(f"✗ Failed to post tweet", file=sys.stderr)
    print(f"Status: {response.status_code}", file=sys.stderr)
    print(f"Response: {response.text}", file=sys.stderr)
    exit(1)
EOF
}

# Upload image to Twitter and get media_id
twitter_upload_image() {
  local image_path="$1"
  
  if [ ! -f "$image_path" ]; then
    echo "Error: Image not found at $image_path" >&2
    return 1
  fi
  
  # Load credentials
  get_twitter_credentials
  
  # Upload to Twitter media endpoint
  local upload_response=$(python3 - "$image_path" <<'EOF'
import requests
from requests_oauthlib import OAuth1
import os
import sys
import json

image_path = sys.argv[1]

consumer_key = os.environ['X_CONSUMER_KEY']
consumer_secret = os.environ['X_CONSUMER_SECRET']
access_token = os.environ['X_ACCESS_TOKEN']
access_token_secret = os.environ['X_ACCESS_TOKEN_SECRET']

auth = OAuth1(consumer_key, consumer_secret, access_token, access_token_secret)

# Upload image
url = "https://upload.twitter.com/1.1/media/upload.json"

with open(image_path, 'rb') as f:
    files = {'media': f}
    response = requests.post(url, auth=auth, files=files)

if response.status_code == 200:
    media_id = response.json()['media_id_string']
    print(media_id)
else:
    print(f"Error: {response.status_code} - {response.text}", file=sys.stderr)
    exit(1)
EOF
)
  
  if [ $? -eq 0 ]; then
    echo "$upload_response"
  else
    return 1
  fi
}

# Post to Twitter with image
twitter_post_with_image() {
  local text="$1"
  local image_path="$2"
  local quote_tweet_id="$3"
  
  echo "Uploading image to Twitter..." >&2
  local media_id=$(twitter_upload_image "$image_path")
  
  if [ $? -ne 0 ]; then
    echo "Failed to upload image to Twitter" >&2
    return 1
  fi
  
  echo "Image uploaded (media_id: $media_id)" >&2
  
  # Load credentials explicitly for posting step
  get_twitter_credentials
  
  # Post with media_id
  python3 - "$text" "$media_id" "${quote_tweet_id:-}" <<'EOF'
import requests
from requests_oauthlib import OAuth1
import os
import sys
import json

text = sys.argv[1]
media_id = sys.argv[2]
quote_id = sys.argv[3] if len(sys.argv) > 3 and sys.argv[3] else None

consumer_key = os.environ['X_CONSUMER_KEY']
consumer_secret = os.environ['X_CONSUMER_SECRET']
access_token = os.environ['X_ACCESS_TOKEN']
access_token_secret = os.environ['X_ACCESS_TOKEN_SECRET']

auth = OAuth1(consumer_key, consumer_secret, access_token, access_token_secret)

url = "https://api.twitter.com/2/tweets"
payload = {
    "text": text,
    "media": {
        "media_ids": [media_id]
    }
}

if quote_id:
    payload["quote_tweet_id"] = quote_id

response = requests.post(url, auth=auth, json=payload)

if response.status_code == 201:
    tweet = response.json()
    tweet_id = tweet['data']['id']
    print(f"✓ Twitter posted: https://twitter.com/user/status/{tweet_id}")
else:
    print(f"✗ Twitter failed: {response.status_code} - {response.text}", file=sys.stderr)
    exit(1)
EOF
}
