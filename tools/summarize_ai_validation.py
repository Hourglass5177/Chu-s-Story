"""Validate production-AI batches and write a reproducible, current-version summary."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from collections import Counter
from pathlib import Path
from statistics import mean

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "artifacts/ai-code-manifest.json"


def source_manifest() -> dict[str, str]:
    paths = list((ROOT / "AI").glob("*.gd")) + [ROOT / name for name in (
        "Managers/interaction_coordinator.gd", "Managers/event_manager.gd", "Managers/food_manager.gd",
        "Managers/market_manager.gd", "Managers/ResouceManager.gd", "Players/player.gd", "地图/map.gd",
    )]
    return {path.relative_to(ROOT).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}


def percentile(values: list[int], fraction: float) -> int:
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, int(len(ordered) * fraction))] if ordered else 0


def read_reports(paths: list[Path], expected: int) -> list[dict]:
    rows = [row for path in paths for row in json.loads(path.read_text(encoding="utf-8"))]
    assert len(rows) == expected, (paths, len(rows), expected)
    assert len({row["index"] for row in rows}) == expected, "Duplicate match configuration"
    for row in rows:
        assert row["completed"] and row["end_reason"] >= 0, (row["index"], "No formal result")
        assert row["result_entry_count"] == row["players"], "Eliminated players must remain ranked"
        assert not row["diagnostics"] and not row["interaction"], row["index"]
        assert row["modals"]["depth"] == row["modals"]["tree_pause_depth"] == 0, row["index"]
        assert row["winner_seats"], "No ranked winner"
    for path in paths:
        log = path.with_suffix(".log")
        contents = log.read_text(encoding="utf-8-sig")
        assert "SCRIPT ERROR" not in contents and "ERROR:" not in contents, log

        assert "WARNING: ObjectDB instances leaked" not in contents and not re.search(r"WARNING: \d+ RIDs? of type .+ leaked", contents), log
        assert contents.count("AI_MATCH ") == len(json.loads(path.read_text(encoding="utf-8"))), "Incomplete batch log"
        assert path.stat().st_mtime >= MANIFEST.stat().st_mtime, "Stale results from an older code snapshot"
    return rows


def summarize(rows: list[dict]) -> dict:
    turns = [row["turns"] for row in rows]
    times = [time for row in rows for time in row["decision_times_us"]]
    result = {
        "matches": len(rows),
        "formal_results": sum(row["completed"] for row in rows),
        "illegal_action_diagnostics": sum(len(row["diagnostics"]) for row in rows),
        "players": dict(sorted(Counter(row["players"] for row in rows).items())),
        "targets": dict(sorted(Counter(row["target"] for row in rows).items())),
        "end_reasons": dict(sorted(Counter(row["end_reason"] for row in rows).items())),
        "turns_mean": round(mean(turns), 2),
        "turns_p95": percentile(turns, .95),
        "turns_max": max(turns),
        "decisions": len(times),
        "decision_us_mean": round(mean(times), 2) if times else 0,
        "decision_us_p95": percentile(times, .95),
        "decision_us_max": max(times, default=0),
        "professions": dict(sorted(Counter(item for row in rows for item in row["professions"]).items())),
        "locations": dict(sorted(Counter(item for row in rows for item in row["locations"]).items())),
    }
    if rows[0]["baseline"] >= 0:
        solo = tied = lost = 0
        for row in rows:
            ai_seat = (row["index"] // 3) % row["players"]
            if ai_seat not in row["winner_seats"]:
                lost += 1
            elif len(row["winner_seats"]) == 1:
                solo += 1
            else:
                tied += 1
        result.update(ai_solo_wins=solo, ai_shared_wins=tied, ai_losses=lost,
                      ai_win_rate_including_ties=round((solo + tied) / len(rows), 4))
    return result


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser()
    parser.add_argument("--normal-only", action="store_true")
    parser.add_argument("--freeze-code", action="store_true")
    args = parser.parse_args()
    if args.freeze_code:
        MANIFEST.write_text(json.dumps(source_manifest(), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"Recorded {len(source_manifest())} AI source hashes")
        return
    assert json.loads(MANIFEST.read_text(encoding="utf-8")) == source_manifest(), "AI source changed after the batch snapshot"
    normal = read_reports([ROOT / f"artifacts/ai-normal-final-{offset}.json" for offset in (0, 324, 648)], 972)
    assert Counter(row["players"] for row in normal) == {2: 324, 3: 324, 6: 324}
    assert Counter((row["players"], row["target"]) for row in normal) == {
        (players, target): 81 for players in (2, 3, 6) for target in (15, 20, 25, 30)
    }
    assert len({(job, place) for row in normal for job, place in zip(row["professions"], row["locations"])}) == 36
    output = {"normal": summarize(normal), "baselines": {}, "notes": [
        "Headless batches use the production controller and policy; presentation waits are omitted.",
        "Decision timings include observation construction; GUI timing is recorded separately.",
        "Legacy baseline strategies do not initiate inheritance challenges; wins are an engineering comparison, not human difficulty evidence.",
    ]}
    if not args.normal_only:
        for index, name in enumerate(("legal_random", "survival_greedy", "score_greedy")):
            rows = read_reports([ROOT / f"artifacts/ai-baseline-final-{index}.json"], 108)
            output["baselines"][name] = summarize(rows)
    destination = ROOT / "artifacts/ai-validation-summary.json"
    destination.write_text(json.dumps(output, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(output, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
