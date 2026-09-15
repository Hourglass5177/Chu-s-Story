"""Run production AI stability/pairing matrices and validate fresh evidence.

Tuning uses separate scripts/seeds. This entry point reserves 930017 for acceptance.
"""
from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import json
import math
from pathlib import Path
import subprocess
import shutil
import time
import os
import ctypes
from contextlib import contextmanager
from collections import Counter

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "artifacts" / "ai-difficulties-final"


def output_resource(name):
    return "res://" + (OUT / name).relative_to(ROOT).as_posix()


def verify_frozen_sources():
    expected = json.loads((OUT / "source-hashes.json").read_text(encoding="utf-8"))
    if expected != sources():
        raise RuntimeError("Sources changed during validation; keep this run separate and start fresh")


@contextmanager
def keep_awake():
    """Request system availability only for this verifier's lifetime; allow screen-off/manual sleep."""
    previous = 0
    if os.name == "nt":
        call = ctypes.windll.kernel32.SetThreadExecutionState
        call.argtypes = [ctypes.c_uint]
        call.restype = ctypes.c_uint
        previous = call(0x80000001)  # ES_CONTINUOUS | ES_SYSTEM_REQUIRED
        if not previous: print("WARNING: Unable to request system availability", flush=True)
    try:
        yield
    finally:
        if previous: call(previous)


def sources():
    paths = []
    for directory in ("AI", "Cards/DataStructure", "Managers", "Players", "UI/Frontend"):
        paths.extend((ROOT / directory).rglob("*.gd"))
        paths.extend((ROOT / directory).rglob("*.tscn"))
    paths.extend(ROOT / name for name in ("main_map.gd", "main_menu.gd", "tools/ai_simulation_runner.gd"))
    return {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(paths)}


def jobs():
    for difficulty in range(3):
        for offset in (0, 324, 648):
            yield f"stability-{difficulty}-{offset}", 324, [f"--difficulty={difficulty}", f"--offset={offset}"]
    yield "mixed", 324, ["--mixed"]
    for low, high in ((0, 1), (1, 2), (0, 2)):
        for unified in (True, False):
            yield f"pair-{low}{high}-{'unified' if unified else 'formal'}", 288, [f"--pair={low},{high}"] + (["--unified-chance"] if unified else [])


def run_job(job, godot, seed, recover=False):
    verify_frozen_sources()
    name, count, flags = job
    if recover:
        return recover_job(job, godot, seed)
    command = [godot, "--headless", "--fixed-fps", "1000", "--path", str(ROOT),
               "res://tools/ai_simulation_runner.tscn", "--", f"--matches={count}",
               f"--seed-base={seed}", f"--output={output_resource(name + '.json')}", *flags]
    with (OUT / f"{name}.log").open("w", encoding="utf-8") as log:
        result = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
    if result.returncode:
        raise RuntimeError(f"{name}: exit {result.returncode}")
    validate(job)
    print(f"PASS {name}: {count}", flush=True)


def recover_job(job, godot, seed):
    """Keep audited finished rows after an interrupted process; never mask a rule failure."""
    name, count, flags = job
    try:
        validate(job)
        print(f"KEEP {name}: {count}", flush=True)
        return
    except (OSError, ValueError, AssertionError, RuntimeError):
        pass
    offset = next((int(f.split("=")[1]) for f in flags if f.startswith("--offset=")), 0)
    expected = set(range(offset, offset + count))
    rows = {}
    inputs = [OUT / f"{name}.log", *sorted(OUT.glob(f"{name}.part-*.log"))]
    for path in inputs:
        if not path.exists(): continue
        content = path.read_text(encoding="utf-8", errors="replace")
        if "ERROR:" in content or "CrashHandler" in content: continue
        for line in content.splitlines():
            if not line.startswith("AI_MATCH "): continue
            row = json.loads(line[9:])
            index = row["index"]
            schedule = index // (2 if name.startswith("pair-") else 3)
            if index not in expected or row["seed"] != seed + row["players"] * 1_000_000 + schedule: continue
            if not row["completed"]:
                # Only explicitly reviewed host interruptions may be retried here.
                # A long elapsed time alone does not prove a machine interruption.
                reviewed_path = OUT / "host-interruptions.json"
                reviewed = json.loads(reviewed_path.read_text(encoding="utf-8")) if reviewed_path.exists() else {}
                record = reviewed.get("games", {}).get(f"{name}:{index}", {})
                if reviewed.get("seed") == seed and record.get("elapsed_ms") == row["elapsed_ms"] and row["elapsed_ms"] >= 120_000:
                    continue
                raise RuntimeError(f"{name}: real unfinished game {index}; investigate before recovery")
            assert not row["diagnostics"], (name, index)
            rows[index] = row
    missing = sorted(expected - rows.keys())
    print(f"RECOVER {name}: keeping {len(rows)}, running {len(missing)}", flush=True)
    original = OUT / f"{name}.log"
    if original.exists(): shutil.copy2(original, OUT / f"{name}.interrupted-{time.time_ns()}.log")
    groups = []
    for index in missing:
        if groups and index == groups[-1][-1] + 1: groups[-1].append(index)
        else: groups.append([index])
    for group in groups:
        part = f"{name}.part-{group[0]}"
        command = [godot, "--headless", "--fixed-fps", "1000", "--path", str(ROOT),
                   "res://tools/ai_simulation_runner.tscn", "--", f"--matches={len(group)}",
                   f"--seed-base={seed}", f"--offset={group[0]}",
                   f"--output={output_resource(part + '.json')}",
                   *[f for f in flags if not f.startswith("--offset=")]]
        with (OUT / f"{part}.log").open("w", encoding="utf-8") as log:
            result = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
        assert result.returncode == 0, (part, result.returncode)
        content = (OUT / f"{part}.log").read_text(encoding="utf-8", errors="replace")
        assert "ERROR:" not in content and "CrashHandler" not in content, part
        for row in json.loads((OUT / f"{part}.json").read_text(encoding="utf-8")):
            rows[row["index"]] = row
        # Checkpoint only completed subprocess results, retaining the original logs separately.
        original.write_text("\n".join("AI_MATCH " + json.dumps(rows[i], ensure_ascii=False) for i in sorted(rows)), encoding="utf-8")
    merged = [rows[i] for i in sorted(expected)]
    (OUT / f"{name}.json").write_text(json.dumps(merged, ensure_ascii=False), encoding="utf-8")
    validate(job)
    print(f"PASS {name}: {count}", flush=True)


def validate(job):
    name, count, flags = job
    text = (OUT / f"{name}.log").read_text(encoding="utf-8", errors="replace")
    if "SCRIPT ERROR:" in text or "ERROR:" in text:
        raise RuntimeError(f"{name}: engine errors")
    rows = json.loads((OUT / f"{name}.json").read_text(encoding="utf-8"))
    assert len(rows) == count, name
    offset = next((int(f.split("=")[1]) for f in flags if f.startswith("--offset=")), int(name.split("-")[-1]) if name.startswith("stability-") else 0)
    assert [r["index"] for r in rows] == list(range(offset, offset + count)), (name, "missing or duplicated indexes")
    seed = json.loads((OUT / "run-config.json").read_text())["seed"]
    for row in rows:
        assert row["unified_chance"] == name.endswith("unified"), (name, "inheritance condition")
        schedule = row["index"] // (2 if name.startswith("pair-") else 3)
        assert row["seed"] == seed + row["players"] * 1_000_000 + schedule, (name, "stale seed")
        assert row["completed"] and not row["diagnostics"], (name, row["index"])
        assert row["result_entry_count"] == row["players"] and row["winner_seats"], name
        assert not row["interaction"], name
        assert row["modals"]["depth"] == 0 and row["modals"]["tree_pause_depth"] == 0, name
        scores = [p["score"] for p in row["final_players"]]
        assert sorted(row["winner_seats"]) == [i for i, score in enumerate(scores) if score == max(scores)], name
        assert len(set(row["professions"])) == row["players"] and len(set(row["locations"])) == row["players"], name
    if name.startswith("pair-"):
        tiers = [int(c) for c in name.split("-")[1]]
        assert all(sorted(r["difficulties"]) == tiers for r in rows), name
        assert Counter(r["target"] for r in rows) == {15: 72, 20: 72, 25: 72, 30: 72}, name
        for first, second in zip(rows[::2], rows[1::2]):
            assert (first["seed"], first["professions"], first["locations"], first["target"]) == (second["seed"], second["professions"], second["locations"], second["target"]), name
            assert first["difficulties"] == second["difficulties"][::-1], name
    return rows


def percentile(values, fraction):
    return sorted(values)[max(0, math.ceil(len(values) * fraction) - 1)]


def summarize(selected_jobs=None):
    selected_jobs = list(jobs()) if selected_jobs is None else list(selected_jobs)
    selected_names = {job[0] for job in selected_jobs}
    result = {}
    failures = []
    for job in selected_jobs:
        name = job[0]
        rows = validate(job)
        times = [t for row in rows for t in row["decision_times_us"]]
        entry = {"games": len(rows), "decisions": len(times), "p95_ms": percentile(times, .95) / 1000,
                 "max_ms": max(times) / 1000, "mean_turns": sum(r["turns"] for r in rows) / len(rows),
                 "end_reasons": {str(reason): sum(r["end_reason"] == reason for r in rows) for reason in sorted({r["end_reason"] for r in rows})}}
        if name.startswith("pair-"):
            high = int(name.split("-")[1][1])
            outcomes = [0.5 if len(r["winner_seats"]) > 1 else float(r["difficulties"][r["winner_seats"][0]] == high) for r in rows]
            wins, ties = outcomes.count(1.0), outcomes.count(0.5)
            rate = sum(outcomes) / len(outcomes)
            # Paired seat rotations share a world seed. CI uses the 144 pair means.
            paired = [(outcomes[i] + outcomes[i + 1]) / 2 for i in range(0, len(outcomes), 2)]
            se = math.sqrt(sum((x - rate) ** 2 for x in paired) / (len(paired) - 1) / len(paired))
            entry.update(wins=wins, ties=ties, losses=len(rows)-wins-ties, adjusted_win_rate=rate,
                         paired_normal_95ci=[max(0, rate-1.96*se), min(1, rate+1.96*se)])
            if name in ("pair-01-unified", "pair-12-unified") and rate < .55:
                failures.append(f"{name}: {rate:.3%} < 55%")
        if name.startswith("stability-"):
            limit = 500 if name.startswith("stability-2-") else 100
            if entry["p95_ms"] > limit: failures.append(f"{name}: P95 {entry['p95_ms']:.2f}ms")
        result[name] = entry
    for difficulty in range(3):
        if not all(f"stability-{difficulty}-{offset}" in selected_names for offset in (0, 324, 648)):
            continue
        rows = [row for offset in (0, 324, 648) for row in validate((f"stability-{difficulty}-{offset}", 324, []))]
        assert Counter(r["players"] for r in rows) == {2: 324, 3: 324, 6: 324}
        assert Counter(r["target"] for r in rows) == {15: 243, 20: 243, 25: 243, 30: 243}
        assert all(set(r["difficulties"]) == {difficulty} for r in rows)
        for count in (2, 3, 6):
            sample = [r for r in rows if r["players"] == count]
            for seat in range(count):
                assert sorted(Counter(r["professions"][seat] for r in sample).values()) == [54] * 6
                assert sorted(Counter(r["locations"][seat] for r in sample).values()) == [54] * 6
    before = json.loads((OUT / "source-hashes.json").read_text(encoding="utf-8"))
    if before != sources(): failures.append("Source changed during validation")
    full_matrix = selected_names == {job[0] for job in jobs()}
    report = {"batches": result, "games": sum(x["games"] for x in result.values()),
              "full_matrix": full_matrix, "failures": failures}
    summary_name = "summary.json" if full_matrix else "summary-selected.json"
    (OUT / summary_name).write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return not failures


def main():
    global OUT
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default="F:/godot 4.7.2/Godot_v4.7.2-stable_win64_console.exe")
    parser.add_argument("--workers", type=int, default=2)
    parser.add_argument("--summarize", action="store_true")
    parser.add_argument("--only", default="")
    parser.add_argument("--resume", action="store_true")
    parser.add_argument("--recover-logs", action="store_true", help="Recover audited completed rows after host/process interruption; requires --resume")
    parser.add_argument("--seed", type=int, default=930017)
    parser.add_argument("--output-dir", default="artifacts/ai-difficulties-final",
                        help="Separate evidence directory under project artifacts; existing evidence requires --resume")
    args = parser.parse_args()
    OUT = (ROOT / args.output_dir).resolve()
    artifact_root = (ROOT / "artifacts").resolve()
    if not OUT.is_relative_to(artifact_root) or OUT == artifact_root:
        parser.error("--output-dir must be a subdirectory of project artifacts")
    if args.workers < 1:
        parser.error("--workers must be positive")
    names = {job[0] for job in jobs()}
    if args.only and not set(args.only.split(",")).issubset(names):
        parser.error("--only contains an unknown batch name")
    assert not args.recover_logs or args.resume, "Recovery requires frozen source/seed verification"
    if not args.resume and not args.summarize and OUT.exists() and any(OUT.iterdir()):
        parser.error("Evidence directory is not empty; use --resume or a new --output-dir")
    OUT.mkdir(parents=True, exist_ok=True)
    if not args.summarize:
        if args.resume:
            assert json.loads((OUT / "source-hashes.json").read_text(encoding="utf-8")) == sources(), "Sources changed; cannot resume"
            assert json.loads((OUT / "run-config.json").read_text())["seed"] == args.seed
        else:
            (OUT / "source-hashes.json").write_text(json.dumps(sources(), indent=2), encoding="utf-8")
            (OUT / "run-config.json").write_text(json.dumps({"seed": args.seed, "workers": args.workers}), encoding="utf-8")
        selected = [job for job in jobs() if not args.only or job[0] in args.only.split(",")]
        if args.resume and not args.recover_logs:
            pending = []
            for job in selected:
                if (OUT / f"{job[0]}.json").exists():
                    validate(job)
                else:
                    pending.append(job)
            selected = pending
        with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as executor:
            futures = [executor.submit(run_job, job, args.godot, args.seed, args.recover_logs) for job in selected]
            for future in concurrent.futures.as_completed(futures): future.result()
        verify_frozen_sources()
        if args.only:
            requested = [job for job in jobs() if job[0] in args.only.split(",")]
            if not summarize(requested): raise SystemExit(1)
            return
    requested = [job for job in jobs() if job[0] in args.only.split(",")] if args.only else None
    raise SystemExit(0 if summarize(requested) else 1)


if __name__ == "__main__":
    with keep_awake():
        main()
