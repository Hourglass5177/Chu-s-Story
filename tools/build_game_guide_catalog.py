#!/usr/bin/env python3
"""Build the runtime digital-guide catalog from its canonical Markdown source."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys


BEGIN = "<!-- GUIDE_CATALOG_BEGIN -->"
END = "<!-- GUIDE_CATALOG_END -->"


def build(source: Path) -> str:
    raw = source.read_bytes()
    text = raw.decode("utf-8")
    start = text.find(BEGIN)
    finish = text.find(END)
    if start < 0 or finish <= start:
        raise ValueError("指南内容缺少 GUIDE_CATALOG_BEGIN/END 标记")
    payload = text[start + len(BEGIN) : finish].strip()
    if payload.startswith("```json") and payload.endswith("```"):
        payload = payload[len("```json") : -len("```")].strip()
    data = json.loads(payload)
    topics = data.get("topics", [])
    ids = [str(topic.get("id", "")) for topic in topics]
    if not ids or any(not topic_id for topic_id in ids):
        raise ValueError("每个指南主题都必须有稳定 ID")
    if len(ids) != len(set(ids)):
        raise ValueError("指南主题 ID 重复")
    known = set(ids)
    for topic in topics:
        missing = [value for value in topic.get("related", []) if value not in known]
        if missing:
            raise ValueError(f"主题 {topic['id']} 关联了不存在的主题：{missing}")
    output = {
        "version": int(data.get("version", 1)),
        "source_sha256": hashlib.sha256(raw).hexdigest(),
        "topics": topics,
    }
    return json.dumps(output, ensure_ascii=False, indent=2, sort_keys=False) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", default="docs/游戏指南内容（数字版）.md")
    parser.add_argument("--output", default="UI/GameGuide/generated/manual_catalog.json")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    source = Path(args.source)
    output = Path(args.output)
    generated = build(source)
    if args.check:
        if not output.exists() or output.read_text(encoding="utf-8") != generated:
            print("数字版指南运行时目录未与源稿同步。", file=sys.stderr)
            return 1
        return 0
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(generated, encoding="utf-8", newline="\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
