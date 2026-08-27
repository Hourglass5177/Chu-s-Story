#!/usr/bin/env python3
"""Build the runtime game-guide catalog from the player-facing Markdown source.

The Markdown file is the only source of player-facing copy. This builder only
adds stable structural IDs, media metadata and discovery requirements; it does
not rewrite or summarize the author's prose.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import sys
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE = ROOT / "docs" / "游戏规则与引导（重写稿）.md"
DEFAULT_MEDIA_SOURCE = ROOT / "docs" / "游戏指南结构与配图（数字版）.json"
DEFAULT_OUTPUT = ROOT / "UI" / "GameGuide" / "generated" / "manual_catalog.json"

RUNTIME_START = "一、快速上手"
RUNTIME_END = "结语"
MEDIA_PREFIXES = ("【配图：", "【卷首主图：")
RESOURCE_SPECS = (
    ("food", ROOT / "Cards" / "食物牌", "food_id"),
    ("event", ROOT / "Cards" / "事件牌", "event_id"),
    ("achievement", ROOT / "Cards" / "成就牌", "achievement_id"),
)

HEADING_RE = re.compile(r"^(#{2,4})\s+(.+?)\s*$")
TITLE_RE = re.compile(r"^#\s+(.+?)\s*$")
NUMBERED_RE = re.compile(r"^(\d+)\.\s+(.+)$")
CHINESE_SECTION_RE = re.compile(r"^[一二三四五六七八九十百〇零]+、\s*")


def _sha256(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def _resource_path(path: Path) -> str:
    return "res://" + path.resolve().relative_to(ROOT).as_posix()


def _load_json(path: Path) -> dict[str, Any]:
    parsed = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(parsed, dict):
        raise ValueError(f"结构清单必须是 JSON 对象：{path}")
    return parsed


def _scan_discovery_entities() -> list[dict[str, str]]:
    entities: list[dict[str, str]] = []
    for kind, root, id_field in RESOURCE_SPECS:
        id_re = re.compile(rf"^{re.escape(id_field)}\s*=\s*&\"([^\"]+)\"\s*$", re.MULTILINE)
        for path in sorted(root.glob("*.tres"), key=lambda value: value.name):
            text = path.read_text(encoding="utf-8")
            id_match = id_re.search(text)
            name_match = re.search(r'^card_name\s*=\s*"(.*)"\s*$', text, re.MULTILINE)
            if id_match is None or name_match is None:
                continue
            entities.append({"kind": kind, "id": id_match.group(1), "name": name_match.group(1)})
    entities.sort(key=lambda value: (-len(value["name"]), value["kind"], value["id"]))
    return entities


def _merge_requirements(*groups: list[dict[str, str]]) -> list[dict[str, str]]:
    result: list[dict[str, str]] = []
    seen: set[tuple[str, str]] = set()
    for group in groups:
        for requirement in group:
            key = (str(requirement.get("kind", "")), str(requirement.get("id", "")))
            if not all(key) or key in seen:
                continue
            seen.add(key)
            result.append({"kind": key[0], "id": key[1]})
    return result


def _requirements_for_text(text: str, entities: list[dict[str, str]]) -> list[dict[str, str]]:
    return [
        {"kind": entity["kind"], "id": entity["id"]}
        for entity in entities
        if entity["name"] and entity["name"] in text
    ]


def _parse_table_row(line: str) -> list[str]:
    stripped = line.strip()
    if stripped.startswith("|"):
        stripped = stripped[1:]
    if stripped.endswith("|"):
        stripped = stripped[:-1]
    return [cell.strip() for cell in stripped.split("|")]


def _table_alignment(cell: str) -> str:
    value = cell.strip()
    left = value.startswith(":")
    right = value.endswith(":")
    if left and right:
        return "center"
    if right:
        return "right"
    return "left"


def _without_chinese_section_number(title: str) -> str:
    """Return a heading's authored title without its display-only chapter number."""
    return CHINESE_SECTION_RE.sub("", title, count=1)


class GuideBuilder:
    def __init__(self, source: Path, media_source: Path) -> None:
        self.source = source
        self.media_source = media_source
        self.source_raw = source.read_bytes()
        self.media_raw = media_source.read_bytes()
        self.lines = self.source_raw.decode("utf-8").splitlines()
        self.structure = _load_json(media_source)
        if int(self.structure.get("schema_version", 0)) != 3:
            raise ValueError("游戏指南结构清单 schema_version 必须为 3")
        self.entities = _scan_discovery_entities()
        self.known_requirements = {(value["kind"], value["id"]) for value in self.entities}
        self.quick_parent = str(self.structure.get("quick_parent_heading", RUNTIME_START))
        self.home_config = dict(self.structure.get("home", {}))
        self.quick_configs = self._index_configs("quick_topics")
        self.rule_configs = self._index_configs("rule_topics")
        self.rule_configs_by_title = self._index_rule_configs_by_title()
        self.media_configs = list(self.structure.get("media", []))
        self._validate_manifest()
        self.matched_media_ids: set[str] = set()
        self.topics: list[dict[str, Any]] = []
        self.current_topic: dict[str, Any] | None = None
        self.current_config: dict[str, Any] | None = None
        self.current_group: dict[str, Any] | None = None
        self.paragraph_lines: list[str] = []
        self.counters: dict[tuple[str, str, str], int] = {}
        self.mode = "outside"
        self.home: dict[str, Any] = {}

    def _index_configs(self, key: str) -> dict[str, dict[str, Any]]:
        values = self.structure.get(key, [])
        if not isinstance(values, list):
            raise ValueError(f"{key} 必须是数组")
        result: dict[str, dict[str, Any]] = {}
        for value in values:
            if not isinstance(value, dict):
                raise ValueError(f"{key} 存在非对象项")
            heading = str(value.get("heading", ""))
            topic_id = str(value.get("id", ""))
            if not heading or not topic_id:
                raise ValueError(f"{key} 的每项都必须有 heading 和 id")
            if heading in result:
                raise ValueError(f"重复的指南标题映射：{heading}")
            result[heading] = value
        return result

    def _index_rule_configs_by_title(self) -> dict[str, dict[str, Any]]:
        result: dict[str, dict[str, Any]] = {}
        for heading, config in self.rule_configs.items():
            title = _without_chinese_section_number(heading)
            if not title or title in result:
                raise ValueError(f"规则主题去除章节编号后重复：{title}")
            result[title] = config
        return result

    def _validate_manifest(self) -> None:
        topic_ids = [str(value["id"]) for value in [*self.quick_configs.values(), *self.rule_configs.values()]]
        if len(topic_ids) != len(set(topic_ids)):
            raise ValueError("结构清单存在重复主题 ID")
        if len(self.quick_configs) != 6 or len(self.rule_configs) != 15:
            raise ValueError("结构清单必须声明 6 个 quick 主题和 15 个 rules 主题")
        home_id = str(self.home_config.get("id", ""))
        home_group_id = str(self.home_config.get("group_id", ""))
        home_display_title = str(self.home_config.get("display_title", ""))
        if not home_id or not home_group_id or not home_display_title:
            raise ValueError("结构清单 home 必须声明稳定 id、group_id 和 display_title")
        topic_group_ids: dict[str, set[str]] = {home_id: {home_group_id}}
        for config in [*self.quick_configs.values(), *self.rule_configs.values()]:
            group_ids = [str(value.get("id", "")) for value in config.get("groups", [])]
            if any(not value for value in group_ids) or len(group_ids) != len(set(group_ids)):
                raise ValueError(f"主题 {config['id']} 存在空白或重复分组 ID")
            group_headings = [str(value.get("heading", "")) for value in config.get("groups", [])]
            if any(not value for value in group_headings) or len(group_headings) != len(set(group_headings)):
                raise ValueError(f"主题 {config['id']} 存在空白或重复分组标题")
            default_group_id = str(config.get("default_group", {}).get("id", ""))
            if not default_group_id:
                raise ValueError(f"主题 {config['id']} 缺少 default_group.id")
            topic_group_ids[str(config["id"])] = {default_group_id, *group_ids}
        aliases = self.structure.get("aliases", {})
        if not isinstance(aliases, dict):
            raise ValueError("aliases 必须是 JSON 对象")
        for alias, target in aliases.items():
            if not str(alias) or str(target) not in topic_ids:
                raise ValueError(f"主题别名无效：{alias} -> {target}")
        media_ids: set[str] = set()
        media_matches: set[str] = set()
        allowed_layouts = {"full", "pair", "sequence", "gallery", "portrait"}
        allowed_fits = {"contain", "cover"}
        media_fallbacks = self.structure.get("media_fallbacks", {})
        if not isinstance(media_fallbacks, dict):
            raise ValueError("media_fallbacks 必须是 JSON 对象")
        for media in self.media_configs:
            if not isinstance(media, dict):
                raise ValueError("媒体清单存在非对象项")
            media_id = str(media.get("id", ""))
            match = str(media.get("match", ""))
            provider = str(media.get("provider", ""))
            if not media_id or media_id in media_ids:
                raise ValueError(f"媒体 ID 空白或重复：{media_id}")
            if not match or match in media_matches:
                raise ValueError(f"媒体匹配文本空白或重复：{match}")
            media_ids.add(media_id)
            media_matches.add(match)
            topic_id = str(media.get("topic_id", ""))
            group_id = str(media.get("group_id", ""))
            if topic_id not in topic_group_ids:
                raise ValueError(f"媒体 {media_id} 指向了不存在的主题")
            if group_id not in topic_group_ids[topic_id]:
                raise ValueError(f"媒体 {media_id} 指向了不存在的分组：{topic_id}.{group_id}")
            if str(media.get("layout", "")) not in allowed_layouts:
                raise ValueError(f"媒体 {media_id} 布局无效")
            if str(media.get("fit", "")) not in allowed_fits:
                raise ValueError(f"媒体 {media_id} 缩放方式无效")
            paths = media.get("paths", [])
            if not isinstance(paths, list):
                raise ValueError(f"媒体 {media_id} paths 必须是数组")
            if provider == "dynamic" and not paths:
                fallback = media_fallbacks.get(str(media.get("dynamic_kind", "")), [])
                if not isinstance(fallback, list):
                    raise ValueError(f"媒体 {media_id} 的动态回退资源必须是数组")
                paths = list(fallback)
                media["paths"] = paths
            if not paths:
                raise ValueError(f"媒体 {media_id} 没有可渲染资源或正式回退资源")
            for value in paths:
                resource_path = str(value)
                if not resource_path.startswith("res://"):
                    raise ValueError(f"媒体 {media_id} 不是 Godot 资源路径：{resource_path}")
                local_path = ROOT / resource_path.removeprefix("res://")
                if not local_path.is_file():
                    raise ValueError(f"媒体 {media_id} 资源不存在：{resource_path}")
                if resource_path.startswith("res://tmp/"):
                    raise ValueError(f"媒体 {media_id} 不得使用临时验证图")
            if provider == "static":
                pass
            elif provider == "dynamic":
                if not str(media.get("dynamic_kind", "")) or not str(media.get("dynamic_id", "")):
                    raise ValueError(f"动态媒体 {media_id} 缺少 dynamic_kind/dynamic_id")
            else:
                raise ValueError(f"媒体 {media_id} provider 无效：{provider}")
            self._validate_requirements(media.get("requirements", []), f"媒体 {media_id}")

    def _validate_requirements(self, requirements: Any, context: str) -> None:
        if not isinstance(requirements, list):
            raise ValueError(f"{context} requirements 必须是数组")
        for requirement in requirements:
            if not isinstance(requirement, dict):
                raise ValueError(f"{context} 存在非对象发现条件")
            key = (str(requirement.get("kind", "")), str(requirement.get("id", "")))
            if key not in self.known_requirements:
                raise ValueError(f"{context} 引用了不存在的发现条件：{key}")

    def build(self) -> dict[str, Any]:
        self.home = self._build_home()
        index = 0
        while index < len(self.lines):
            line = self.lines[index]
            heading_match = HEADING_RE.match(line)
            if heading_match:
                self._flush_paragraph()
                level = len(heading_match.group(1))
                title = heading_match.group(2)
                if level == 2 and title == RUNTIME_END:
                    self._finish_topic()
                    self.mode = "finished"
                    break
                self._handle_heading(level, title)
                index += 1
                continue
            if self.mode in ("outside", "quick_parent", "finished"):
                index += 1
                continue
            if not line.strip():
                self._flush_paragraph()
                index += 1
                continue
            if line.startswith(MEDIA_PREFIXES):
                self._flush_paragraph()
                self._add_media(line)
                index += 1
                continue
            if line.strip() == "---":
                self._flush_paragraph()
                next_content = self._next_nonempty(index + 1)
                if next_content is not None and not next_content.startswith("## "):
                    self._add_section("divider", {})
                index += 1
                continue
            if line.startswith("- "):
                self._flush_paragraph()
                items: list[str] = []
                while index < len(self.lines) and self.lines[index].startswith("- "):
                    items.append(self.lines[index][2:])
                    index += 1
                self._add_list("bullets", items)
                continue
            if NUMBERED_RE.match(line):
                self._flush_paragraph()
                items = []
                while index < len(self.lines):
                    match = NUMBERED_RE.match(self.lines[index])
                    if match is None:
                        break
                    items.append(match.group(2))
                    index += 1
                self._add_list("numbered", items)
                continue
            if line.lstrip().startswith("|"):
                self._flush_paragraph()
                table_lines: list[str] = []
                while index < len(self.lines) and self.lines[index].lstrip().startswith("|"):
                    table_lines.append(self.lines[index])
                    index += 1
                self._add_table(table_lines)
                continue
            if line.startswith(">"):
                self._flush_paragraph()
                quote_lines: list[str] = []
                while index < len(self.lines) and self.lines[index].startswith(">"):
                    quote_lines.append(self.lines[index][1:].lstrip())
                    index += 1
                self._add_text_section("quote", "\n".join(quote_lines))
                continue
            self.paragraph_lines.append(line)
            index += 1

        self._flush_paragraph()
        self._finish_topic()
        self._validate_result()
        return {
            "schema_version": 3,
            "source_path": _resource_path(self.source),
            "source_sha256": _sha256(self.source_raw),
            "media_source_path": _resource_path(self.media_source),
            "media_source_sha256": _sha256(self.media_raw),
            "home": self.home,
            "aliases": dict(self.structure.get("aliases", {})),
            "topics": self.topics,
        }

    def _build_home(self) -> dict[str, Any]:
        title = ""
        home_id = str(self.home_config["id"])
        group_id = str(self.home_config["group_id"])
        sections: list[dict[str, Any]] = []
        paragraph_lines: list[str] = []
        paragraph_ordinal = 0

        def flush_paragraph() -> None:
            nonlocal paragraph_ordinal
            if not paragraph_lines:
                return
            paragraph_ordinal += 1
            text = "\n".join(paragraph_lines)
            paragraph_lines.clear()
            sections.append({
                "id": f"{home_id}.{group_id}.paragraph.{paragraph_ordinal:02d}",
                "group_id": group_id,
                "type": "paragraph",
                "text": text,
                "requirements": _requirements_for_text(text, self.entities),
            })

        in_home = False
        for line in self.lines:
            title_match = TITLE_RE.match(line)
            if title_match and not in_home:
                title = title_match.group(1)
                in_home = True
                continue
            if not in_home:
                continue
            if line.startswith("## 目录"):
                flush_paragraph()
                break
            if line.startswith(MEDIA_PREFIXES):
                flush_paragraph()
                sections.append(self._build_home_media(line, home_id, group_id))
                continue
            if line.startswith(">"):
                flush_paragraph()
                continue
            if not line.strip():
                flush_paragraph()
                continue
            paragraph_lines.append(line)
        if not title:
            raise ValueError("重写稿缺少 H1 标题")
        if not sections:
            raise ValueError("重写稿卷首没有可展示正文")
        return {
            "id": home_id,
            "title": str(self.home_config["display_title"]),
            "sections": sections,
        }

    def _build_home_media(self, instruction: str, home_id: str, group_id: str) -> dict[str, Any]:
        matches = [
            value
            for value in self.media_configs
            if str(value.get("match", "")) and str(value["match"]) in instruction
        ]
        if len(matches) != 1:
            raise ValueError(f"卷首配图指令必须唯一匹配媒体清单：{instruction}")
        config = matches[0]
        media_id = str(config["id"])
        if str(config.get("topic_id", "")) != home_id or str(config.get("group_id", "")) != group_id:
            raise ValueError(f"卷首媒体 {media_id} 的归属配置错误")
        if media_id in self.matched_media_ids:
            raise ValueError(f"媒体 ID 重复使用：{media_id}")
        self.matched_media_ids.add(media_id)
        entry = {key: value for key, value in config.items() if key not in {"match", "topic_id", "group_id"}}
        entry["requirements"] = list(entry.get("requirements", []))
        return {
            "id": f"{home_id}.{group_id}.media.{media_id}",
            "group_id": group_id,
            "type": "media",
            "media_entries": [entry],
            "requirements": [],
        }

    def _handle_heading(self, level: int, title: str) -> None:
        if level == 2:
            if title == self.quick_parent:
                self._finish_topic()
                self.mode = "quick_parent"
                return
            rule_config = self.rule_configs_by_title.get(_without_chinese_section_number(title))
            if rule_config is not None:
                self._finish_topic()
                self.mode = "rules"
                self._start_topic(rule_config, title, "rules")
                return
            if self.mode in ("quick_parent", "quick", "rules"):
                raise ValueError(f"运行时正文缺少稳定主题映射：{title}")
            return
        if level == 3 and self.mode in ("quick_parent", "quick"):
            config = self.quick_configs.get(title)
            if config is None:
                raise ValueError(f"快速上手缺少稳定主题映射：{title}")
            self._finish_topic()
            self.mode = "quick"
            self._start_topic(config, title, "quick")
            return
        if level == 3 and self.mode == "rules":
            self._start_named_group(title, level)
            return
        if level == 4 and self.mode == "quick":
            self._start_named_group(title, level)
            return
        if self.current_topic is not None:
            self._add_text_section("heading", title, {"level": level})

    def _start_topic(self, config: dict[str, Any], title: str, category: str) -> None:
        topic_id = str(config["id"])
        self.current_config = config
        self.current_topic = {
            "id": topic_id,
            "category": category,
            "title": title,
            "summary": "",
            "summary_id": f"{topic_id}.summary",
            "summary_requirements": [],
            "groups": [],
            "sections": [],
        }
        default_group = config.get("default_group", {"id": "overview", "title": ""})
        self.current_group = self._ensure_group(
            str(default_group.get("id", "overview")),
            str(default_group.get("title", "")),
            [],
        )

    def _start_named_group(self, title: str, level: int) -> None:
        if self.current_topic is None or self.current_config is None:
            raise ValueError(f"指南小节没有所属主题：{title}")
        self._flush_paragraph()
        group_configs = self.current_config.get("groups", [])
        match = next((value for value in group_configs if str(value.get("heading", "")) == title), None)
        if match is None:
            raise ValueError(f"主题 {self.current_topic['id']} 缺少稳定分组映射：{title}")
        requirements = _requirements_for_text(title, self.entities)
        self.current_group = self._ensure_group(str(match["id"]), title, requirements)
        self._add_text_section("heading", title, {"level": level})

    def _ensure_group(
        self,
        group_id: str,
        title: str,
        requirements: list[dict[str, str]],
    ) -> dict[str, Any]:
        assert self.current_topic is not None
        existing = next((value for value in self.current_topic["groups"] if value["id"] == group_id), None)
        if existing is not None:
            return existing
        group = {"id": group_id, "title": title, "requirements": requirements, "section_ids": []}
        self.current_topic["groups"].append(group)
        return group

    def _finish_topic(self) -> None:
        self._flush_paragraph()
        if self.current_topic is None:
            self.current_config = None
            self.current_group = None
            return
        default_group_id = str(
            self.current_config.get("default_group", {}).get("id", "overview")
            if self.current_config is not None
            else "overview"
        )
        default_group = next(
            (value for value in self.current_topic["groups"] if value["id"] == default_group_id),
            None,
        )
        if default_group is not None:
            first_id = default_group["section_ids"][0] if default_group["section_ids"] else ""
            first_section = next(
                (value for value in self.current_topic["sections"] if value["id"] == first_id),
                None,
            )
            if first_section is not None and first_section["type"] == "paragraph":
                self.current_topic["summary"] = first_section["text"]
                self.current_topic["summary_id"] = first_section["id"]
                self.current_topic["summary_requirements"] = first_section["requirements"]
                self.current_topic["sections"].remove(first_section)
                default_group["section_ids"].remove(first_section["id"])
        self.current_topic["groups"] = [
            value
            for value in self.current_topic["groups"]
            if value["section_ids"] or value["id"] != default_group_id
        ]
        self.topics.append(self.current_topic)
        self.current_topic = None
        self.current_config = None
        self.current_group = None

    def _flush_paragraph(self) -> None:
        if not self.paragraph_lines:
            return
        text = "\n".join(self.paragraph_lines)
        self.paragraph_lines.clear()
        if self.current_topic is not None:
            self._add_text_section("paragraph", text)

    def _next_nonempty(self, start: int) -> str | None:
        for index in range(start, len(self.lines)):
            if self.lines[index].strip():
                return self.lines[index]
        return None

    def _group_requirements(self) -> list[dict[str, str]]:
        if self.current_group is None:
            return []
        return list(self.current_group.get("requirements", []))

    def _next_id(self, section_type: str) -> str:
        if self.current_topic is None or self.current_group is None:
            raise ValueError("无法为没有主题或分组的内容生成 ID")
        key = (self.current_topic["id"], self.current_group["id"], section_type)
        ordinal = self.counters.get(key, 0) + 1
        self.counters[key] = ordinal
        return f"{key[0]}.{key[1]}.{section_type}.{ordinal:02d}"

    def _add_section(self, section_type: str, payload: dict[str, Any]) -> dict[str, Any]:
        if self.current_topic is None or self.current_group is None:
            raise ValueError(f"内容块缺少所属主题：{section_type}")
        section = {
            "id": self._next_id(section_type),
            "group_id": self.current_group["id"],
            "type": section_type,
            **payload,
        }
        section.setdefault("requirements", self._group_requirements())
        self.current_topic["sections"].append(section)
        self.current_group["section_ids"].append(section["id"])
        return section

    def _add_text_section(
        self,
        section_type: str,
        text: str,
        extra: dict[str, Any] | None = None,
    ) -> None:
        requirements = _merge_requirements(
            self._group_requirements(),
            _requirements_for_text(text, self.entities),
        )
        payload: dict[str, Any] = {"text": text, "requirements": requirements}
        if extra:
            payload.update(extra)
        self._add_section(section_type, payload)

    def _add_list(self, section_type: str, texts: list[str]) -> None:
        section_id = self._next_id(section_type)
        inherited = self._group_requirements()
        items = []
        for ordinal, text in enumerate(texts, 1):
            items.append({
                "id": f"{section_id}.item.{ordinal:02d}",
                "text": text,
                "requirements": _merge_requirements(
                    inherited,
                    _requirements_for_text(text, self.entities),
                ),
            })
        section = {
            "id": section_id,
            "group_id": self.current_group["id"],
            "type": section_type,
            "items": items,
            "requirements": inherited,
        }
        self.current_topic["sections"].append(section)
        self.current_group["section_ids"].append(section_id)

    def _add_table(self, lines: list[str]) -> None:
        if len(lines) < 2:
            self._add_text_section("paragraph", "\n".join(lines))
            return
        headers = _parse_table_row(lines[0])
        delimiter = _parse_table_row(lines[1])
        if len(headers) != len(delimiter) or not all(re.fullmatch(r":?-{3,}:?", value) for value in delimiter):
            self._add_text_section("paragraph", "\n".join(lines))
            return
        section_id = self._next_id("table")
        inherited = self._group_requirements()
        rows = []
        for ordinal, line in enumerate(lines[2:], 1):
            cells = _parse_table_row(line)
            if len(cells) != len(headers):
                raise ValueError(f"表格 {section_id} 第 {ordinal} 行列数与表头不一致")
            rows.append({
                "id": f"{section_id}.row.{ordinal:02d}",
                "cells": cells,
                "requirements": _merge_requirements(
                    inherited,
                    _requirements_for_text("\n".join(cells), self.entities),
                ),
            })
        section = {
            "id": section_id,
            "group_id": self.current_group["id"],
            "type": "table",
            "table_headers": headers,
            "table_alignments": [_table_alignment(value) for value in delimiter],
            "table_rows": rows,
            "requirements": inherited,
        }
        self.current_topic["sections"].append(section)
        self.current_group["section_ids"].append(section_id)

    def _add_media(self, instruction: str) -> None:
        if self.current_topic is None or self.current_group is None:
            return
        matches = [
            value
            for value in self.media_configs
            if str(value.get("match", "")) and str(value["match"]) in instruction
        ]
        if len(matches) != 1:
            raise ValueError(f"配图指令必须唯一匹配媒体清单：{instruction}")
        config = matches[0]
        media_id = str(config.get("id", ""))
        if not media_id:
            raise ValueError(f"配图清单缺少稳定 ID：{instruction}")
        expected_topic = str(config.get("topic_id", ""))
        expected_group = str(config.get("group_id", ""))
        if expected_topic and expected_topic != self.current_topic["id"]:
            raise ValueError(f"媒体 {media_id} 应属于 {expected_topic}，实际出现在 {self.current_topic['id']}")
        if expected_group and expected_group != self.current_group["id"]:
            raise ValueError(f"媒体 {media_id} 应属于 {expected_group}，实际出现在 {self.current_group['id']}")
        if media_id in self.matched_media_ids:
            raise ValueError(f"媒体 ID 重复使用：{media_id}")
        self.matched_media_ids.add(media_id)
        entry = {key: value for key, value in config.items() if key not in {"match", "topic_id", "group_id"}}
        explicit_requirements = [
            {"kind": str(value.get("kind", "")), "id": str(value.get("id", ""))}
            for value in entry.get("requirements", [])
            if isinstance(value, dict)
        ]
        entry["requirements"] = _merge_requirements(self._group_requirements(), explicit_requirements)
        section = self._add_section(
            "media",
            {"media_entries": [entry], "requirements": self._group_requirements()},
        )
        old_id = section["id"]
        section["id"] = f"{self.current_topic['id']}.{self.current_group['id']}.media.{media_id}"
        self.current_group["section_ids"][-1] = section["id"]
        if old_id == section["id"]:
            return

    def _validate_result(self) -> None:
        quick = [value for value in self.topics if value["category"] == "quick"]
        rules = [value for value in self.topics if value["category"] == "rules"]
        if len(quick) != 6 or len(rules) != 15:
            raise ValueError(f"指南主题数量错误：quick={len(quick)} rules={len(rules)}")
        expected_quick_ids = {str(value["id"]) for value in self.quick_configs.values()}
        expected_rule_ids = {str(value["id"]) for value in self.rule_configs.values()}
        if {str(value["id"]) for value in quick} != expected_quick_ids:
            raise ValueError("快速上手主题与结构清单不一致")
        if {str(value["id"]) for value in rules} != expected_rule_ids:
            raise ValueError("详细规则主题与结构清单不一致")
        ids: set[str] = set()
        nested_ids: set[str] = set()
        allowed_types = {"heading", "paragraph", "bullets", "numbered", "table", "quote", "media", "divider"}
        for topic in self.topics:
            topic_id = str(topic["id"])
            if topic_id in ids:
                raise ValueError(f"主题 ID 重复：{topic_id}")
            ids.add(topic_id)
            group_ids = {str(value["id"]) for value in topic["groups"]}
            if len(group_ids) != len(topic["groups"]):
                raise ValueError(f"主题 {topic_id} 存在重复分组 ID")
            config = next(
                value
                for value in [*self.quick_configs.values(), *self.rule_configs.values()]
                if str(value["id"]) == topic_id
            )
            declared_named_groups = {str(value["id"]) for value in config.get("groups", [])}
            if not declared_named_groups.issubset(group_ids):
                missing = sorted(declared_named_groups - group_ids)
                raise ValueError(f"主题 {topic_id} 缺少结构清单分组：{missing}")
            section_ids = {str(value["id"]) for value in topic["sections"]}
            if len(section_ids) != len(topic["sections"]):
                raise ValueError(f"主题 {topic_id} 存在重复内容块 ID")
            for group in topic["groups"]:
                if any(section_id not in section_ids for section_id in group["section_ids"]):
                    raise ValueError(f"主题 {topic_id} 分组 {group['id']} 引用了不存在的内容块")
                self._validate_requirements(group.get("requirements", []), f"分组 {topic_id}.{group['id']}")
            self._validate_requirements(topic.get("summary_requirements", []), f"主题 {topic_id} 摘要")
            for section in topic["sections"]:
                if section["type"] not in allowed_types:
                    raise ValueError(f"内容块类型无效：{section['type']}")
                if section["group_id"] not in group_ids:
                    raise ValueError(f"内容块 {section['id']} 缺少有效分组")
                if section["id"] in nested_ids:
                    raise ValueError(f"内容块 ID 全局重复：{section['id']}")
                nested_ids.add(section["id"])
                self._validate_generated_section(section)
        if self.home.get("id") != self.home_config.get("id") or not self.home.get("title"):
            raise ValueError("卷首内容缺少稳定 ID 或标题")
        home_sections = self.home.get("sections", [])
        if not isinstance(home_sections, list) or not home_sections:
            raise ValueError("卷首内容没有可展示区块")
        for section in home_sections:
            section_id = str(section.get("id", ""))
            if not section_id or section_id in nested_ids:
                raise ValueError(f"卷首内容块 ID 空白或重复：{section_id}")
            nested_ids.add(section_id)
            self._validate_generated_section(section)
        declared_media_ids = {str(value.get("id", "")) for value in self.media_configs}
        unmatched = declared_media_ids - self.matched_media_ids
        if unmatched:
            raise ValueError(f"媒体清单存在未匹配项：{sorted(unmatched)}")
        generated = json.dumps({"home": self.home, "topics": self.topics}, ensure_ascii=False)
        if "【配图：" in generated or "【卷首主图：" in generated:
            raise ValueError("运行时目录泄露了配图制作指令")
        if "本文是游戏内数字版规则与引导的唯一正文源" in generated:
            raise ValueError("运行时目录泄露了源稿状态说明")
        if "tmp/" in generated or "res://tmp/" in generated:
            raise ValueError("运行时目录引用了临时验证资源")

    def _validate_generated_section(self, section: dict[str, Any]) -> None:
        section_id = str(section.get("id", ""))
        allowed_types = {"heading", "paragraph", "bullets", "numbered", "table", "quote", "media", "divider"}
        if str(section.get("type", "")) not in allowed_types:
            raise ValueError(f"内容块类型无效：{section.get('type', '')}")
        self._validate_requirements(section.get("requirements", []), f"内容块 {section_id}")
        section_type = str(section.get("type", ""))
        if section_type in {"bullets", "numbered"}:
            item_ids: set[str] = set()
            for item in section.get("items", []):
                item_id = str(item.get("id", ""))
                if not item_id or item_id in item_ids:
                    raise ValueError(f"列表项 ID 空白或重复：{item_id}")
                item_ids.add(item_id)
                self._validate_requirements(item.get("requirements", []), f"列表项 {item.get('id', '')}")
        elif section_type == "table":
            headers = section.get("table_headers", [])
            row_ids: set[str] = set()
            for row in section.get("table_rows", []):
                row_id = str(row.get("id", ""))
                if not row_id or row_id in row_ids:
                    raise ValueError(f"表格行 ID 空白或重复：{row_id}")
                row_ids.add(row_id)
                if len(row.get("cells", [])) != len(headers):
                    raise ValueError(f"表格行 {row.get('id', '')} 与表头列数不一致")
                self._validate_requirements(row.get("requirements", []), f"表格行 {row.get('id', '')}")
        elif section_type == "media":
            entries = section.get("media_entries", [])
            if not entries:
                raise ValueError(f"媒体块 {section_id} 没有媒体条目")
            for entry in entries:
                paths = entry.get("paths", [])
                if not isinstance(paths, list) or not paths:
                    raise ValueError(f"媒体 {entry.get('id', '')} 没有可渲染资源")
                self._validate_requirements(entry.get("requirements", []), f"媒体 {entry.get('id', '')}")


def build(source: Path = DEFAULT_SOURCE, media_source: Path = DEFAULT_MEDIA_SOURCE) -> str:
    data = GuideBuilder(source.resolve(), media_source.resolve()).build()
    return json.dumps(data, ensure_ascii=False, indent=2, sort_keys=False) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--media-source", type=Path, default=DEFAULT_MEDIA_SOURCE)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    try:
        generated = build(args.source, args.media_source)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError, ValueError) as error:
        print(f"数字版指南构建失败：{error}", file=sys.stderr)
        return 1
    if args.check:
        if not args.output.exists() or args.output.read_text(encoding="utf-8") != generated:
            print("数字版指南运行时目录未与重写稿同步。", file=sys.stderr)
            return 1
        return 0
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(generated, encoding="utf-8", newline="\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
