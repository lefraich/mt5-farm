#!/usr/bin/env python3
"""Stream farm tool - download channel videos (newest first) and build playlists.

Commands:
  agent <channel_url> <index> <count> <outdir>
       downloads videos ids[index::count] (round-robin subset), newest first,
       then writes <outdir>/playlist.txt in concat format (newest first).
  master <channel_url> <outdir>
       downloads ALL videos newest first, writes <outdir>/playlist_all.txt.
"""
import argparse
import pathlib
import re
import subprocess
import sys


def ytdlp(args):
    return subprocess.run(
        [sys.executable, "-m", "yt_dlp"] + args, capture_output=True, text=True
    )


def get_videos(channel_url):
    """Return video ids from the channel /videos tab, in the order YouTube lists them (newest first)."""
    url = channel_url.rstrip("/")
    if not url.endswith("/videos"):
        url += "/videos"
    r = ytdlp(["--flat-playlist", "--print", "%(id)s", url])
    if r.returncode != 0:
        raise SystemExit("yt-dlp list failed:\n" + r.stderr[-3000:])
    ids = [ln for ln in r.stdout.splitlines() if re.fullmatch(r"[A-Za-z0-9_-]{11}", ln)]
    if not ids:
        raise SystemExit("no videos found at " + url)
    return ids


def download(ids, outdir):
    outdir = pathlib.Path(outdir)
    outdir.mkdir(parents=True, exist_ok=True)
    urls = ["https://www.youtube.com/watch?v=" + i for i in ids]
    # download in batches of 8 to avoid overlong command lines
    for k in range(0, len(urls), 8):
        batch = urls[k:k + 8]
        r = ytdlp([
            "-f", "bv*[height<=720]+ba/b[height<=720]",
            "--merge-output-format", "mp4",
            "--no-playlist",
            "--no-overwrites",
            "--no-part",
            "-o", str(outdir / "%(id)s.%(ext)s"),
            *batch,
        ])
        if r.returncode != 0:
            print("download warnings/errors (continuing):", r.stderr[-2000:], file=sys.stderr)


def build_playlist(ids, outdir, playlist_file):
    outdir = pathlib.Path(outdir).resolve()
    outdir.mkdir(parents=True, exist_ok=True)
    lines = []
    for vid in ids:
        cands = list(outdir.glob(vid + ".*"))
        if not cands:
            print("missing video, skipping:", vid, file=sys.stderr)
            continue
        f = str(cands[0]).replace("\\", "/")
        lines.append("file '" + f + "'")
    pathlib.Path(playlist_file).write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("playlist ->", playlist_file, "(", len(lines), "entries )")


def cmd_agent(channel_url, index, count, outdir, limit=0):
    ids = get_videos(channel_url)
    subset = ids[index::count]
    if limit and limit > 0:
        subset = subset[:limit]
    print("videos found:", len(ids), "| my subset (newest first):", len(subset))
    download(subset, outdir)
    build_playlist(subset, outdir, pathlib.Path(outdir) / "playlist.txt")


def cmd_master(channel_url, outdir):
    ids = get_videos(channel_url)
    print("videos found (newest first):", len(ids))
    download(ids, outdir)
    build_playlist(ids, outdir, pathlib.Path(outdir) / "playlist_all.txt")


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    a = sub.add_parser("agent")
    a.add_argument("channel_url")
    a.add_argument("index", type=int)
    a.add_argument("count", type=int)
    a.add_argument("outdir")
    a.add_argument("--limit", type=int, default=0)
    m = sub.add_parser("master")
    m.add_argument("channel_url")
    m.add_argument("outdir")
    args = ap.parse_args()
    if args.cmd == "agent":
        cmd_agent(args.channel_url, args.index, args.count, args.outdir, args.limit)
    else:
        cmd_master(args.channel_url, args.outdir)


if __name__ == "__main__":
    main()
