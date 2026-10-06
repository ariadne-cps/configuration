#!/usr/bin/env python3
import argparse
import json
import os
import sys
from collections import defaultdict


def _as_bool(value):
    return bool(value)


def _line_coverage(segments):
    """Reconstruct llvm-cov line coverage from exported segments.

    Returns {line: execution_count} for mapped source lines. The logic mirrors
    llvm-cov's line iterator closely enough to preserve source line semantics
    across isolated per-test exports.
    """
    if not segments:
        return {}

    normalized = []
    for raw in segments:
        if len(raw) < 6:
            continue
        normalized.append({
            "line": int(raw[0]),
            "col": int(raw[1]),
            "count": int(raw[2]),
            "has_count": _as_bool(raw[3]),
            "region_entry": _as_bool(raw[4]),
            "gap": _as_bool(raw[5]),
        })
    if not normalized:
        return {}
    normalized.sort(key=lambda s: (s["line"], s["col"]))

    by_line = defaultdict(list)
    for seg in normalized:
        by_line[seg["line"]].append(seg)

    first_line = normalized[0]["line"]
    last_line = normalized[-1]["line"]
    wrapped = None
    result = {}

    for line in range(first_line, last_line + 1):
        line_segments = by_line.get(line, [])
        starts_skipped = bool(
            line_segments
            and not line_segments[0]["has_count"]
            and line_segments[0]["region_entry"]
        )

        region_starts = [
            seg for seg in line_segments
            if seg["region_entry"] and seg["has_count"] and not seg["gap"]
        ]

        mapped = False
        count = 0
        if not starts_skipped and wrapped is not None and wrapped["has_count"]:
            mapped = True
            count = wrapped["count"]

        if region_starts:
            mapped = True
            count = max([count] + [seg["count"] for seg in region_starts])

        if mapped:
            result[line] = count

        if line_segments:
            wrapped = line_segments[-1]

    return result


def _function_definition(function, known_files):
    filenames = function.get("filenames", [])
    candidates = []
    for region in function.get("regions", []):
        if len(region) < 8 or region[7] != 0:
            continue
        file_id = int(region[5])
        if 0 <= file_id < len(filenames):
            filename = os.path.normpath(filenames[file_id])
            if filename in known_files:
                candidates.append((int(region[0]), int(region[1]), filename))
    if not candidates:
        for region in function.get("regions", []):
            if len(region) < 7:
                continue
            file_id = int(region[5])
            if 0 <= file_id < len(filenames):
                filename = os.path.normpath(filenames[file_id])
                if filename in known_files:
                    candidates.append((int(region[0]), int(region[1]), filename))
    if not candidates:
        return None
    line, col, filename = min(candidates)
    return filename, line, col


def _branch_records(file_record):
    for raw in file_record.get("branches", []):
        if len(raw) < 6:
            continue
        line_start = int(raw[0])
        col_start = int(raw[1])
        line_end = int(raw[2])
        col_end = int(raw[3])
        true_count = int(raw[4])
        false_count = int(raw[5])
        kind = raw[8] if len(raw) > 8 else 0
        yield (line_start, col_start, line_end, col_end, kind), true_count, false_count


def _pct(covered, total):
    if total == 0:
        return "-"
    return f"{100.0 * covered / total:.2f}%"


def _display_name(filename, source_root):
    try:
        rel = os.path.relpath(filename, source_root)
        if not rel.startswith(".." + os.sep) and rel != "..":
            return rel.replace(os.sep, "/")
    except ValueError:
        pass
    return filename.replace(os.sep, "/")


def _safe_function_name(name, line, col):
    name = name or f"function@{line}:{col}"
    return name.replace("\n", " ").replace("\r", " ").replace(",", ";")


def aggregate(paths):
    lines = defaultdict(lambda: defaultdict(int))
    functions = {}
    branches = defaultdict(lambda: defaultdict(lambda: [0, 0]))
    known_files = set()

    documents = []
    for path in paths:
        with open(path, "r", encoding="utf-8") as handle:
            document = json.load(handle)
        if document.get("type") != "llvm.coverage.json.export":
            raise ValueError(f"{path}: not an llvm-cov JSON export")
        documents.append(document)
        for datum in document.get("data", []):
            for file_record in datum.get("files", []):
                known_files.add(os.path.normpath(file_record["filename"]))

    for document in documents:
        for datum in document.get("data", []):
            for file_record in datum.get("files", []):
                filename = os.path.normpath(file_record["filename"])
                for line, count in _line_coverage(file_record.get("segments", [])).items():
                    lines[filename][line] += count
                for key, true_count, false_count in _branch_records(file_record):
                    entry = branches[filename][key]
                    entry[0] += true_count
                    entry[1] += false_count

            for function in datum.get("functions", []):
                definition = _function_definition(function, known_files)
                if definition is None:
                    continue
                filename, line, col = definition
                key = (filename, line, col)
                count = int(function.get("count", 0))
                name = function.get("name", "")
                if key not in functions:
                    functions[key] = {"count": count, "name": name}
                else:
                    functions[key]["count"] += count
                    current = functions[key]["name"]
                    if not current or (name and len(name) < len(current)):
                        functions[key]["name"] = name

    return lines, functions, branches


def build_stats(lines, functions, branches):
    files = set(lines) | set(branches) | {key[0] for key in functions}
    result = {}
    for filename in sorted(files):
        file_functions = [
            (key, value) for key, value in functions.items() if key[0] == filename
        ]
        function_total = len(file_functions)
        function_hit = sum(1 for _, value in file_functions if value["count"] > 0)

        file_lines = lines.get(filename, {})
        line_total = len(file_lines)
        line_hit = sum(1 for count in file_lines.values() if count > 0)

        file_branches = branches.get(filename, {})
        branch_total = 2 * len(file_branches)
        branch_hit = sum(
            (1 if counts[0] > 0 else 0) + (1 if counts[1] > 0 else 0)
            for counts in file_branches.values()
        )

        if function_total or line_total or branch_total:
            result[filename] = {
                "functions": function_total,
                "functions_hit": function_hit,
                "lines": line_total,
                "lines_hit": line_hit,
                "branches": branch_total,
                "branches_hit": branch_hit,
            }
    return result


def render_table(stats, source_root):
    headers = [
        "Filename", "Functions", "Missed Functions", "Executed",
        "Lines", "Missed Lines", "Cover", "Branches", "Missed Branches", "Cover",
    ]
    rows = []
    for filename, s in stats.items():
        rows.append([
            _display_name(filename, source_root),
            str(s["functions"]),
            str(s["functions"] - s["functions_hit"]),
            _pct(s["functions_hit"], s["functions"]),
            str(s["lines"]),
            str(s["lines"] - s["lines_hit"]),
            _pct(s["lines_hit"], s["lines"]),
            str(s["branches"]),
            str(s["branches"] - s["branches_hit"]),
            _pct(s["branches_hit"], s["branches"]),
        ])

    total = {
        key: sum(s[key] for s in stats.values())
        for key in ["functions", "functions_hit", "lines", "lines_hit", "branches", "branches_hit"]
    }
    total_row = [
        "TOTAL",
        str(total["functions"]),
        str(total["functions"] - total["functions_hit"]),
        _pct(total["functions_hit"], total["functions"]),
        str(total["lines"]),
        str(total["lines"] - total["lines_hit"]),
        _pct(total["lines_hit"], total["lines"]),
        str(total["branches"]),
        str(total["branches"] - total["branches_hit"]),
        _pct(total["branches_hit"], total["branches"]),
    ]

    widths = [len(h) for h in headers]
    for row in rows + [total_row]:
        for i, value in enumerate(row):
            widths[i] = max(widths[i], len(value))

    def fmt(row):
        return "  ".join(
            value.ljust(widths[i]) if i == 0 else value.rjust(widths[i])
            for i, value in enumerate(row)
        )

    separator = "  ".join("-" * width for width in widths)
    output = [fmt(headers), separator]
    output.extend(fmt(row) for row in rows)
    output.append(separator)
    output.append(fmt(total_row))
    return "\n".join(output), total


def write_lcov(path, lines, functions, branches):
    files = sorted(set(lines) | set(branches) | {key[0] for key in functions})
    with open(path, "w", encoding="utf-8") as out:
        for filename in files:
            file_lines = lines.get(filename, {})
            file_functions = sorted(
                [(key, value) for key, value in functions.items() if key[0] == filename],
                key=lambda item: (item[0][1], item[0][2], item[1]["name"]),
            )
            file_branches = sorted(branches.get(filename, {}).items())
            if not file_lines and not file_functions and not file_branches:
                continue

            out.write(f"SF:{filename}\n")
            used_names = defaultdict(int)
            function_names = []
            for key, value in file_functions:
                _, line, col = key
                base = _safe_function_name(value["name"], line, col)
                used_names[base] += 1
                name = base if used_names[base] == 1 else f"{base}#{used_names[base]}"
                function_names.append((line, name, value["count"]))
                out.write(f"FN:{line},{name}\n")
            for _, name, count in function_names:
                out.write(f"FNDA:{count},{name}\n")
            if function_names:
                out.write(f"FNF:{len(function_names)}\n")
                out.write(
                    f"FNH:{sum(1 for _, _, count in function_names if count > 0)}\n"
                )

            for line, count in sorted(file_lines.items()):
                out.write(f"DA:{line},{count}\n")
            if file_lines:
                out.write(f"LF:{len(file_lines)}\n")
                out.write(
                    f"LH:{sum(1 for count in file_lines.values() if count > 0)}\n"
                )

            branch_index = 0
            branch_hit = 0
            for key, counts in file_branches:
                line = key[0]
                for side, count in enumerate(counts):
                    out.write(f"BRDA:{line},{branch_index},{side},{count}\n")
                    if count > 0:
                        branch_hit += 1
                branch_index += 1
            if file_branches:
                out.write(f"BRF:{2 * len(file_branches)}\n")
                out.write(f"BRH:{branch_hit}\n")

            out.write("end_of_record\n")


def main():
    parser = argparse.ArgumentParser(
        description="Merge isolated llvm-cov JSON exports."
    )
    parser.add_argument("--source-root", required=True)
    parser.add_argument("--output-lcov", required=True)
    parser.add_argument("reports", nargs="+")
    args = parser.parse_args()

    source_root = os.path.normpath(os.path.abspath(args.source_root))
    lines, functions, branches = aggregate(args.reports)
    stats = build_stats(lines, functions, branches)
    table, total = render_table(stats, source_root)
    write_lcov(args.output_lcov, lines, functions, branches)

    print(table)
    print(
        f"TOTAL_COUNTS functions={total['functions']} "
        f"lines={total['lines']} branches={total['branches']}"
    )
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print(f"error: {exc}", file=sys.stderr)
        sys.exit(1)
