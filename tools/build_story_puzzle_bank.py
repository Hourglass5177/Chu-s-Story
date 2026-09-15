"""Build and independently verify true shortest-distance 8-puzzle banks."""
from collections import deque
from pathlib import Path
import argparse
import json
import random

OUTPUT = Path(__file__).resolve().parents[1] / "InheritanceTasks/Data/story-puzzle-bank-v1.json"
GOAL = (1, 2, 3, 4, 5, 6, 7, 8, 0)

def neighbors(board):
    blank = board.index(0)
    for offset, action in ((-1, -1), (1, 1), (-3, -2), (3, 2)):
        target = blank + offset
        if not 0 <= target < 9 or (abs(offset) == 1 and target // 3 != blank // 3):
            continue
        moved = list(board)
        moved[blank], moved[target] = moved[target], moved[blank]
        yield tuple(moved), action

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    distances = {GOAL: 0}
    pending = deque([GOAL])
    while pending:
        board = pending.popleft()
        for moved, _ in neighbors(board):
            if moved not in distances:
                distances[moved] = distances[board] + 1
                pending.append(moved)
    assert len(distances) == 181440 and max(distances.values()) == 31
    if args.check:
        data = json.loads(OUTPUT.read_text(encoding="utf-8"))
    else:
        rng = random.Random(20260914)
        data = {"version": 1, "goal": GOAL, "direction_semantics": "move_empty_cell", "reachable_count": len(distances), "maximum_depth": 31, "by_depth": {}}
        for depth in range(10, 17):
            candidates = sorted(board for board, distance in distances.items() if distance == depth)
            entries = []
            for board in rng.sample(candidates, 64):
                cursor, solution = board, []
                while cursor != GOAL:
                    cursor, action = next((moved, action) for moved, action in neighbors(cursor) if distances[moved] == distances[cursor] - 1)
                    solution.append(action)
                entries.append({"board": board, "solution": solution})
            data["by_depth"][str(depth)] = entries
        OUTPUT.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    seen = set()
    for depth, entries in data["by_depth"].items():
        for entry in entries:
            board = tuple(entry["board"])
            assert tuple(sorted(board)) == tuple(range(9)) and board not in seen
            seen.add(board)
            assert distances[board] == int(depth) == len(entry["solution"])
            for direction in entry["solution"]:
                board = next(moved for moved, action in neighbors(board) if action == direction)
            assert board == GOAL
    print(f"Verified {len(seen)} unique candidates against {len(distances)} reachable boards; exact depths 10–16.")

if __name__ == "__main__":
    main()
