"""The build: World -> validate -> pack -> emit -> report (pipeline.md stages). Deterministic."""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path

from bastians_build import links, steps
from bastians_build.config import BuildConfig, PackConfig
from bastians_build.emit import (
    HEADER,
    emit_pack,
    emit_transforms,
    lazy_index,
    locale_guard,
    lua_value,
)
from bastians_build.files import write_text
from bastians_build.groundtruth import Check, render_section
from bastians_build.model import World, parse_ref
from bastians_build.pack import pack_table, record_counts
from bastians_build.probetruth import ProbeTruth, render_probe_section


@dataclass
class PackResult:
    pack: PackConfig
    path: Path
    size: int
    counts: dict[str, int]
    index_counts: dict[str, int]
    changed: bool
    index_bytes: dict[str, int] = field(default_factory=dict)  # each index's bytes in the file
    # build.toml [limits] pack_kb (ADR 0072): no budget, the size above which a pack is a build
    # gone wrong
    ceiling_kb: int | None = None

    @property
    def over_ceiling(self) -> bool:
        return self.ceiling_kb is not None and self.size > self.ceiling_kb * 1024


@dataclass
class BuildResult:
    world: World
    packs: list[PackResult] = field(default_factory=list)
    problems: list[str] = field(default_factory=list)
    notes: list[str] = field(default_factory=list)
    skipped: list[str] = field(default_factory=list)  # optional packs without records
    ground_truth: list[Check] | None = None  # groundtruth.compare, when a CSV was given
    probe_truth: ProbeTruth | None = None  # probetruth.check_probe, when a probe dump was given
    steps: steps.Report | None = None  # the quests' steps as the build resolved them
    report: str = ""
    report_path: Path | None = None
    links_path: Path | None = None  # links-<client>.json, the counts the edition keeps
    transforms_path: Path | None = None
    transforms_changed: bool = False

    @property
    def ok(self) -> bool:
        return not self.problems and not any(p.over_ceiling for p in self.packs)


# ForeverDB's licence (GPL-3.0 section 7(b)): the line that starts "-- Data: ForeverDB.net
# (https://foreverdb.net)" stays with its data. The market's and the book's packs hold none of it.
FDB_CREDIT = "Data: ForeverDB.net (https://foreverdb.net), among other sources: see the About page"
FDB_PACKS = frozenset({"world", "quests", "items", "text"})


def pack_comment(name: str, world: World, localized: bool = False) -> str:
    """The comment lines under a pack's header: what it is, and ForeverDB's credit if it holds its
    data. The first line stays the pack's: tools/release.py reads the client from it."""
    comment = f"pack {name} for {world.client}, build {world.build}"
    has_fdb = any(source.startswith("ForeverDB") for source in world.sources)
    if has_fdb and (name in FDB_PACKS or localized):
        comment += f"\n-- {FDB_CREDIT}"
    return comment


def validate(world: World, config: BuildConfig) -> list[str]:
    """Referential integrity: every ref in `starts`/`ends` points at a known type (pipeline.md)."""
    problems: list[str] = []
    for quest_id, rec in sorted(world.records.get("quest", {}).items()):
        for field_name in ("starts", "ends"):
            for ref in rec.get(field_name) or []:
                try:
                    ref_type, _ = parse_ref(ref)
                except ValueError:
                    problems.append(f"quest {quest_id}: {field_name} has a bad ref {ref!r}")
                    continue
                if config.pack_for_type(ref_type) is None:
                    problems.append(
                        f"quest {quest_id}: {field_name} refers to unknown type {ref_type!r}"
                    )
    for record_type, rows in world.records.items():
        if config.pack_for_type(record_type) is None:
            problems.append(f"type {record_type!r} ({len(rows)} rows) is in no pack schema")
    return problems


def build(
    world: World,
    config: BuildConfig,
    out_dir: Path,
    *,
    write: bool = True,
    transforms: dict | None = None,
    report_dir: Path | None = None,
    ground_truth: list[Check] | None = None,
    transforms_source: str | None = None,
    continent_names: dict[int, str] | None = None,
    probe_truth: ProbeTruth | None = None,
) -> BuildResult:
    result = BuildResult(world=world, ground_truth=ground_truth, probe_truth=probe_truth)
    result.problems = validate(world, config)
    # every quest's steps, resolved on the finished world (steps.py): the entrances and whatever
    # else joined the world after the sources were merged are in it by now
    result.steps = steps.resolve(world)
    result.notes = list(world.notes)
    if result.problems:
        return result
    if transforms:
        table = {m: t.row() for m, t in sorted(transforms.items())}
        exact = sum(1 for t in transforms.values() if t.exact)
        continents = sorted({t.continent for t in transforms.values()})
        text = emit_transforms(
            table,
            comment=f"{len(table)} maps on {len(continents)} continents, {exact} exact; "
            f"{world.client}; from {transforms_source or 'the probe dump'}",
            continents=continent_names,
        )
        path = out_dir / "Bastians_Data" / "Generated" / "MapTransforms.lua"
        changed = write_text(path, text) if write else False
        result.transforms_path = path
        result.transforms_changed = changed
    if write:
        # the loader's TOC lists the CurseForge download counts, which only the daily edition
        # writes (tools/data_update.py): a stub that registers nothing, as for an empty pack
        stub = (
            f"{HEADER}\n-- no download counts in this {world.client} build "
            "(tools/data_update.py writes them into the daily edition)\n"
        )
        write_text(out_dir / "Bastians_Data" / "Generated" / "Downloads.lua", stub)
    for name in config.pack_order:
        cfg = config.packs[name]
        if cfg.optional and not any(world.count(t) for t in cfg.schema):
            # a stub so the client finds the file its TOC lists (BugSack showed "Error loading
            # .../Generated/Market.lua" on every login, 21.10.2026); it registers nothing
            result.skipped.append(name)
            stub = (
                f"{HEADER}\n-- pack {name}: no data in this {world.client} build (optional pack)\n"
            )
            if write:
                write_text(out_dir / cfg.addon / "Generated" / cfg.file, stub)
            continue
        table = pack_table(world, cfg)
        text = emit_pack(
            name, table, comment=pack_comment(name, world, bool(cfg.locales)), lazy=links.LAZY
        )
        if cfg.locales:
            text = locale_guard(text, cfg.locales)
        path = out_dir / cfg.addon / "Generated" / cfg.file
        changed = write_text(path, text) if write else False
        result.packs.append(
            PackResult(
                pack=cfg,
                path=path,
                size=len(text.encode("utf-8")),
                counts=record_counts(world, cfg),
                index_counts={k: len(v) for k, v in table["index"].items()},
                changed=changed,
                index_bytes={
                    k: len(lua_value(lazy_index(v) if k in links.LAZY else v, 3).encode("utf-8"))
                    for k, v in table["index"].items()
                },
                ceiling_kb=config.pack_ceiling_kb,
            )
        )
    report = render_report(result)
    result.report = report
    if write:
        folder = report_dir or out_dir
        result.report_path = folder / "report.md"
        write_text(result.report_path, report)
        # the count and the lists (data.md "The count and the watch"): what the edition keeps,
        # the watch compares and a player with a low character can go and check
        client = world.client
        result.links_path = folder / f"links-{client}.json"
        counts = json.dumps(links_counts(result), indent=1, sort_keys=True)
        write_text(result.links_path, counts + "\n")
        write_text(folder / f"links-classic-{client}.tsv", steps.listing(result.steps.classic))
        write_text(
            folder / f"links-unplaced-{client}.tsv",
            steps.listing(result.steps.open, reasons=True),
        )
    return result


def edge_sizes(result: BuildResult) -> dict[str, tuple[int, int]]:
    """Each `edge.*` index a pack of this build carries: (its keys, its bytes in the file)."""
    return {
        name: (p.index_counts[name], p.index_bytes.get(name, 0))
        for p in result.packs
        for name in p.index_counts
        if name in links.BY_INDEX
    }


def links_counts(result: BuildResult) -> dict:
    """`links-<client>.json`: the steps' numbers and the edge indexes' sizes. No time in it: the
    same inputs give the same file."""
    world = result.world
    return {
        "client": world.client,
        "build": world.build,
        **result.steps.counts(),
        "edges": {
            name: {"keys": keys, "bytes": size}
            for name, (keys, size) in sorted(edge_sizes(result).items())
        },
    }


def render_links(result: BuildResult) -> list[str]:
    """The edge registry in the report (data.md "The edge registry"): how many links each edge
    stores and what the index of its other direction costs in its pack."""
    counts = links.counts(result.world)
    sizes = edge_sizes(result)
    lines = [
        "## Links",
        "",
        "| Edge | From | To | Links stored | The other direction | Keys | Size |",
        "|---|---|---|---|---|---|---|",
    ]
    for e in links.EDGES:
        if e.index is None:
            other, keys, size = e.why or "-", "-", "-"
        elif e.index in sizes:
            other = e.index
            keys, size = str(sizes[e.index][0]), f"{sizes[e.index][1] / 1024:.1f} KB"
        else:
            other, keys, size = f"{e.index} (its pack is not built)", "-", "-"
        lines.append(
            f"| {e.name} | {', '.join(e.src)} | {', '.join(e.dst)} | {counts[e.name]} "
            f"| {other} | {keys} | {size} |"
        )
    return [*lines, ""]


def _named(counts: dict[str, int]) -> str:
    return ", ".join(f"{name} {n}" for name, n in counts.items()) or "none"


def render_steps(result: BuildResult) -> list[str]:
    """The quests' steps as the resolver placed them (data.md "The count and the watch"): by
    kind, what places them, what is known of the ones without a place, and the Classic debt by
    zone. The lists themselves are the two files beside the report."""
    c = result.steps.counts()
    client = result.world.client
    lines = [
        "## Quest steps",
        "",
        f"{c['steps']} steps in {c['quests'] - c['quests_without_steps']} of {c['quests']} quests.",
        "",
        "| Kind | Steps | With a place |",
        "|---|---|---|",
    ]
    lines += [
        f"| {kind} | {row['steps']} | {row['placed']} |" for kind, row in c["steps_by_kind"].items()
    ]
    lines += [
        "",
        f"- With a place: {c['placed']} ({_named(c['placed_by_src'])}; `subject` is the "
        "subject's own places).",
        f"- No place needed: {c['given']} (the item the giver hands over).",
        f"- Without a place: {c['unplaced']} ({_named(c['unplaced_by_reason'])}). "
        f"The list: `links-unplaced-{client}.tsv`.",
        f"- **The Classic debt**: {c['classic']} steps placed by Classic knowledge alone. "
        f"The list, the lowest quest level first: `links-classic-{client}.tsv`.",
        "",
    ]
    if c["classic_by_zone"]:
        by_zone = sorted(c["classic_by_zone"].items(), key=lambda pair: (-pair[1], pair[0]))
        lines += ["| Zone | Classic-only steps |", "|---|---|"]
        lines += [f"| {zone} | {n} |" for zone, n in by_zone]
        lines.append("")
    if result.steps.assumed:
        # our own table's rows without `verified` (data.md "Our authored table"): listed in
        # every report until somebody checked them in game
        lines += [
            f"**Authored places to check in game** ({_count(len(result.steps.assumed), 'step')}; "
            f"`quest_places_{client}.toml`, the rows without `verified`):",
            "",
            "| Quest | Step | Subject | Zone | Level |",
            "|---|---|---|---|---|",
        ]
        for row in result.steps.assumed:
            name = f"{row.quest} {row.name}" if row.name else str(row.quest)
            subject = row.subject or row.ref or "-"
            level = "-" if row.level is None else row.level
            lines.append(f"| {name} | {row.step} | {subject} | {row.zone or '-'} | {level} |")
        lines.append("")
    return lines


def _count(n: int, word: str) -> str:
    return f"{n} {word}" if n == 1 else f"{n} {word}s"


def render_report(result: BuildResult) -> str:
    """build/report.md: sizes, counts, dropped rows; no timestamps. A pack has no size budget
    (ADR 0072): the table names the one ceiling and marks a pack above it."""
    world = result.world
    lines = [
        "# Build report",
        "",
        f"Client: {world.client}. Build: {world.build}. "
        f"Sources: {', '.join(world.sources) or 'none'}.",
        "",
    ]
    if result.problems:
        lines += ["## Validation failed", ""] + [f"- {p}" for p in result.problems] + [""]
        return "\n".join(lines)
    lines += [
        "## Packs",
        "",
        "| Pack | Addon | Size | Ceiling | Records | Indexes |",
        "|---|---|---|---|---|---|",
    ]
    for p in result.packs:
        budget = f"{p.ceiling_kb} KB" if p.ceiling_kb else "-"
        flag = " **ABOVE THE CEILING**" if p.over_ceiling else ""
        records = ", ".join(f"{t} {n}" for t, n in sorted(p.counts.items()))
        indexes = ", ".join(f"{k} {n}" for k, n in sorted(p.index_counts.items())) or "-"
        lines.append(
            f"| {p.pack.name} | {p.pack.addon} | {p.size / 1024:.1f} KB{flag} | {budget} "
            f"| {records} | {indexes} |"
        )
    lines.append("")
    lines += render_links(result)
    if result.steps is not None:
        lines += render_steps(result)
    if result.notes:
        lines += ["## Notes", ""] + [f"- {n}" for n in result.notes] + [""]
    if result.ground_truth is not None:
        lines += render_section(result.ground_truth)
    if result.probe_truth is not None:
        lines += render_probe_section(result.probe_truth)
    lines += ["## Dropped rows", ""]
    if world.dropped:
        by_reason: dict[str, list] = {}
        for record_type, record_id, reason in world.dropped:
            by_reason.setdefault(reason, []).append(f"{record_type} {record_id}")
        for reason in sorted(by_reason):
            ids = sorted(set(by_reason[reason]), key=str)
            shown = ", ".join(ids[:20]) + (f", ... ({len(ids)} in all)" if len(ids) > 20 else "")
            lines.append(f"- {reason}: {len(by_reason[reason])} rows: {shown}")
    else:
        lines.append("none")
    lines.append("")
    return "\n".join(lines)
