"""The build: World -> validate -> pack -> emit -> report (pipeline.md stages). Deterministic."""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path

from bastians_build.config import BuildConfig, PackConfig
from bastians_build.emit import HEADER, emit_pack, emit_transforms
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
    budget_kb: int | None = None  # the budget of the built client (build.toml, per client)

    @property
    def over_budget(self) -> bool:
        return self.budget_kb is not None and self.size > self.budget_kb * 1024


@dataclass
class BuildResult:
    world: World
    packs: list[PackResult] = field(default_factory=list)
    problems: list[str] = field(default_factory=list)
    notes: list[str] = field(default_factory=list)
    skipped: list[str] = field(default_factory=list)  # optional packs without records
    ground_truth: list[Check] | None = None  # groundtruth.compare, when a CSV was given
    probe_truth: ProbeTruth | None = None  # probetruth.check_probe, when a probe dump was given
    report: str = ""
    report_path: Path | None = None
    transforms_path: Path | None = None
    transforms_changed: bool = False

    @property
    def ok(self) -> bool:
        return not self.problems and not any(p.over_budget for p in self.packs)


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
            name, table, comment=f"pack {name} for {world.client}, build {world.build}"
        )
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
                budget_kb=cfg.budget_for(world.client),
            )
        )
    report = render_report(result)
    result.report = report
    if write:
        result.report_path = (report_dir or out_dir) / "report.md"
        write_text(result.report_path, report)
    return result


def render_report(result: BuildResult) -> str:
    """build/report.md: sizes against budgets, counts, dropped rows; no timestamps."""
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
        "| Pack | Addon | Size | Budget | Records | Indexes |",
        "|---|---|---|---|---|---|",
    ]
    for p in result.packs:
        budget = f"{p.budget_kb} KB" if p.budget_kb else "-"
        flag = " **OVER**" if p.over_budget else ""
        records = ", ".join(f"{t} {n}" for t, n in sorted(p.counts.items()))
        indexes = ", ".join(f"{k} {n}" for k, n in sorted(p.index_counts.items())) or "-"
        lines.append(
            f"| {p.pack.name} | {p.pack.addon} | {p.size / 1024:.1f} KB{flag} | {budget} "
            f"| {records} | {indexes} |"
        )
    lines.append("")
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
