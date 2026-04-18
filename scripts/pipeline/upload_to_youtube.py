#!/usr/bin/env python3
"""
upload_to_youtube.py
Uploads a generated lofi video to the YouTube channel 'llooffiisounds'.

Auth: OAuth2 (first run opens browser, then saves token.json for headless reuse)
      OR service account (set GOOGLE_APPLICATION_CREDENTIALS env var)

Usage:
  python upload_to_youtube.py --video lofi-output.mp4 --title "lofi beats • 3 hours" --description "..."
"""

import argparse
import datetime
import json
import os
import pickle
import sys
from pathlib import Path

# ---------------------------------------------------------------------------
# YouTube API title/description templates
# ---------------------------------------------------------------------------
MOODS = ["chill", "rainy evening", "late night", "study", "focus", "coffee shop", "midnight"]
VIBES = ["relax/study to", "work/focus to", "sleep to", "code to", "read to"]

def generate_title() -> str:
    mood = __import__("random").choice(MOODS)
    vibe = __import__("random").choice(VIBES)
    return f"lofi hip hop • {mood} beats to {vibe} 🎵 3 hour mix"

def generate_description(title: str) -> str:
    now = datetime.datetime.utcnow()
    return f"""{title}

A continuous 3-hour lofi mix generated with the Lofi Engine.

🎵 Perfect for studying, working, or relaxing.
🌙 No ads, no interruptions — just pure lofi vibes.

➤ Subscribe to llooffiisounds for daily lofi drops
➤ Turn on notifications 🔔 so you never miss a mix

Generated: {now.strftime('%Y-%m-%d')}

#lofi #lofihiphop #studymusic #chillbeats #relaxingmusic #focusmusic #lofimix"""

TAGS = [
    "lofi", "lofi hip hop", "study music", "chill beats", "relax music",
    "focus music", "lofi mix", "3 hours lofi", "beats to study to",
    "lofi chill", "ambient music", "background music", "lofi 2025",
]

# ---------------------------------------------------------------------------
# Auth
# ---------------------------------------------------------------------------
TOKEN_PATH = Path(__file__).parent / "youtube_token.pickle"
CLIENT_SECRET_PATH = Path(__file__).parent / "client_secret.json"
SCOPES = ["https://www.googleapis.com/auth/youtube.upload"]


def get_credentials():
    creds = None

    if TOKEN_PATH.exists():
        with open(TOKEN_PATH, "rb") as f:
            creds = pickle.load(f)

    if creds and creds.valid:
        return creds

    try:
        from google.auth.transport.requests import Request
        from google_auth_oauthlib.flow import InstalledAppFlow
    except ImportError:
        print("Missing deps: pip install google-auth-oauthlib google-auth-httplib2 google-api-python-client")
        sys.exit(1)

    if creds and creds.expired and creds.refresh_token:
        creds.refresh(Request())
    else:
        if not CLIENT_SECRET_PATH.exists():
            print(f"\n[auth] Missing {CLIENT_SECRET_PATH}")
            print("  1. Go to https://console.cloud.google.com/")
            print("  2. Create a project → Enable YouTube Data API v3")
            print("  3. Create OAuth2 credentials (Desktop app) → download JSON")
            print(f"  4. Save as: {CLIENT_SECRET_PATH}")
            sys.exit(1)

        flow = InstalledAppFlow.from_client_secrets_file(str(CLIENT_SECRET_PATH), SCOPES)
        # On Oracle VM: use --noauth_local_webserver flow
        creds = flow.run_local_server(port=0) if _has_display() else flow.run_console()

    with open(TOKEN_PATH, "wb") as f:
        pickle.dump(creds, f)

    return creds


def _has_display() -> bool:
    return bool(os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY"))


# ---------------------------------------------------------------------------
# Upload
# ---------------------------------------------------------------------------
def upload_video(video_path: Path, title: str, description: str, tags: list[str],
                 privacy: str = "public", category_id: str = "10") -> str:
    try:
        from googleapiclient.discovery import build
        from googleapiclient.http import MediaFileUpload
    except ImportError:
        print("Missing deps: pip install google-api-python-client")
        sys.exit(1)

    creds = get_credentials()
    youtube = build("youtube", "v3", credentials=creds)

    body = {
        "snippet": {
            "title": title[:100],
            "description": description[:5000],
            "tags": tags[:500],
            "categoryId": category_id,  # 10 = Music
        },
        "status": {
            "privacyStatus": privacy,
            "selfDeclaredMadeForKids": False,
        },
    }

    media = MediaFileUpload(
        str(video_path),
        mimetype="video/mp4",
        resumable=True,
        chunksize=1024 * 1024 * 8,  # 8MB chunks
    )

    print(f"\n[youtube] Uploading: {video_path.name}")
    print(f"  Title: {title}")
    print(f"  Privacy: {privacy}")

    request = youtube.videos().insert(part="snippet,status", body=body, media_body=media)
    response = None
    while response is None:
        status, response = request.next_chunk()
        if status:
            pct = int(status.progress() * 100)
            print(f"  Uploading... {pct}%", end="\r")

    video_id = response["id"]
    url = f"https://www.youtube.com/watch?v={video_id}"
    print(f"\n  ✓ Uploaded: {url}")

    # Save upload log
    log_path = Path(__file__).parent / "upload_log.json"
    log = []
    if log_path.exists():
        try:
            log = json.loads(log_path.read_text())
        except Exception:
            pass
    log.append({
        "id": video_id,
        "url": url,
        "title": title,
        "uploaded_at": datetime.datetime.utcnow().isoformat(),
        "file": str(video_path),
    })
    log_path.write_text(json.dumps(log, indent=2))

    return video_id


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--video", required=True, help="Path to the MP4 file")
    parser.add_argument("--title", default=None, help="Video title (auto-generated if omitted)")
    parser.add_argument("--description", default=None, help="Video description")
    parser.add_argument("--privacy", default="public", choices=["public", "private", "unlisted"])
    args = parser.parse_args()

    video_path = Path(args.video)
    if not video_path.exists():
        print(f"File not found: {video_path}")
        sys.exit(1)

    title = args.title or generate_title()
    description = args.description or generate_description(title)

    upload_video(video_path, title, description, TAGS, privacy=args.privacy)


if __name__ == "__main__":
    main()
