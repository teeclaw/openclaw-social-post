#!/bin/bash
#
# fetch-tweet.sh - Fetch tweet content via Twitter API v2
#
# Usage:
#   fetch-tweet.sh <tweet_id_or_url> [--account <name>] [--json]
#
# Examples:
#   fetch-tweet.sh 2021593178709667948
#   fetch-tweet.sh https://x.com/i/status/2021593178709667948
#   fetch-tweet.sh 123456789 --json
#   fetch-tweet.sh 123456789 --account oxdasx
#

set -euo pipefail

# --- Defaults ---
ACCOUNT_PREFIX="X_"
OUTPUT_JSON=false

# --- Parse arguments ---
TWEET_INPUT=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --account)
      ACCOUNT_PREFIX="${2^^}_"
      shift 2
      ;;
    --json)
      OUTPUT_JSON=true
      shift
      ;;
    -*)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
    *)
      if [[ -z "$TWEET_INPUT" ]]; then
        TWEET_INPUT="$1"
      else
        echo "Too many arguments" >&2
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$TWEET_INPUT" ]]; then
  echo "Usage: $0 <tweet_id_or_url> [--account <name>] [--json]" >&2
  exit 1
fi

# --- Extract tweet ID from URL or use directly ---
if [[ "$TWEET_INPUT" =~ ^https?:// ]]; then
  # Extract ID from URL
  TWEET_ID=$(echo "$TWEET_INPUT" | sed -n 's|.*/status/\([0-9]*\).*|\1|p')
  if [[ -z "$TWEET_ID" ]]; then
    echo "Error: Could not extract tweet ID from URL: $TWEET_INPUT" >&2
    exit 1
  fi
else
  TWEET_ID="$TWEET_INPUT"
fi

# Validate tweet ID is numeric
if ! [[ "$TWEET_ID" =~ ^[0-9]+$ ]]; then
  echo "Error: Invalid tweet ID: $TWEET_ID" >&2
  exit 1
fi

# --- Load credentials ---
ENV_FILE="${HOME}/.openclaw/.env"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "Error: Credentials file not found: $ENV_FILE" >&2
  exit 1
fi

# Try to load bearer token first (preferred for read operations)
BEARER_TOKEN=$(grep -E "^${ACCOUNT_PREFIX}BEARER_TOKEN=" "$ENV_FILE" | cut -d= -f2- | tr -d '"' | head -1)

if [[ -z "$BEARER_TOKEN" ]]; then
  echo "Error: Missing Twitter Bearer Token for account prefix: $ACCOUNT_PREFIX" >&2
  echo "Required variable: ${ACCOUNT_PREFIX}BEARER_TOKEN" >&2
  echo "Get it from: https://developer.twitter.com/en/portal/dashboard" >&2
  exit 1
fi

# --- Fetch tweet ---
API_URL="https://api.twitter.com/2/tweets/${TWEET_ID}"
QUERY_PARAMS="tweet.fields=created_at,author_id,public_metrics,conversation_id,in_reply_to_user_id,referenced_tweets&expansions=author_id&user.fields=username,name"
FULL_URL="${API_URL}?${QUERY_PARAMS}"

# Make API request with Bearer token
RESPONSE=$(curl -s -X GET "$FULL_URL" \
  -H "Authorization: Bearer $BEARER_TOKEN" \
  -H "User-Agent: OpenClaw-Twitter-Fetch/1.0")

# Check for errors
if echo "$RESPONSE" | jq -e '.errors' >/dev/null 2>&1; then
  echo "Error fetching tweet:" >&2
  echo "$RESPONSE" | jq -r '.errors[] | "- \(.title): \(.detail)"' >&2
  exit 1
fi

# Check if tweet data exists
if ! echo "$RESPONSE" | jq -e '.data' >/dev/null 2>&1; then
  echo "Error: No tweet data in response" >&2
  echo "$RESPONSE" >&2
  exit 1
fi

# --- Output results ---
if [[ "$OUTPUT_JSON" == true ]]; then
  echo "$RESPONSE"
else
  # Pretty print
  echo "=== Tweet Details ==="
  echo
  
  # Extract data
  TWEET_TEXT=$(echo "$RESPONSE" | jq -r '.data.text')
  AUTHOR_USERNAME=$(echo "$RESPONSE" | jq -r '.includes.users[0].username // "unknown"')
  AUTHOR_NAME=$(echo "$RESPONSE" | jq -r '.includes.users[0].name // "Unknown"')
  CREATED_AT=$(echo "$RESPONSE" | jq -r '.data.created_at')
  LIKES=$(echo "$RESPONSE" | jq -r '.data.public_metrics.like_count // 0')
  RETWEETS=$(echo "$RESPONSE" | jq -r '.data.public_metrics.retweet_count // 0')
  REPLIES=$(echo "$RESPONSE" | jq -r '.data.public_metrics.reply_count // 0')
  
  echo "Author: $AUTHOR_NAME (@$AUTHOR_USERNAME)"
  echo "Posted: $CREATED_AT"
  echo "Tweet ID: $TWEET_ID"
  echo "URL: https://x.com/${AUTHOR_USERNAME}/status/${TWEET_ID}"
  echo
  echo "Content:"
  echo "─────────────────────────────────────────────"
  echo "$TWEET_TEXT"
  echo "─────────────────────────────────────────────"
  echo
  echo "Engagement:"
  echo "  ❤️  Likes: $LIKES"
  echo "  🔄 Retweets: $RETWEETS"
  echo "  💬 Replies: $REPLIES"
  echo
fi
