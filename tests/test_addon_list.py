"""The game's AddOn list: every
shipped addon is either an app under the one category "Bastian's Suite" or a child of an app's group
(the data packs under Bastian's Data, the map's art and styles under Bastian's Map), so the list
shows one folded header and one row per app. Both clients read `## Group` and `## Category`
(Blizzard_AddOnList, read from Forever 1.60.1.70707 and retail 12.1.5, 02.11.2026). Every shipped
addon carries its notes in German, French, Spanish (esMX reads esES's), Korean and both Chinese,
and a title in them where it has a part to translate (core.md "The AddOn list")."""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from check_toc import parse_toc  # noqa: E402
from release import DEV_ONLY  # noqa: E402

ADDONS = ROOT / "addons"
CATEGORY = "Bastian's Suite"
ASIAN = ("koKR", "zhCN", "zhTW")
LATIN = ("deDE", "frFR", "esES", "esMX")
CJK = re.compile(r"[ᄀ-ᇿ぀-ヿ㐀-鿿가-힣]")


def shipped() -> dict[str, dict[str, str]]:
    out = {}
    for toc in sorted(ADDONS.glob("*/*.toc")):
        if toc.stem == toc.parent.name and toc.stem not in DEV_ONLY:
            out[toc.stem] = parse_toc(toc.read_text(encoding="utf-8"))[0]
    return out


def test_every_addon_is_an_app_of_the_category_or_in_an_apps_group():
    tocs = shipped()
    apps = {name for name, meta in tocs.items() if "Group" not in meta}
    for name, meta in tocs.items():
        if "Group" in meta:
            parent = meta["Group"]
            assert parent in apps, (name, parent)  # one level: the parent is an app
            assert "Category" not in meta, name  # a child follows its parent
            assert parent in meta.get("Dependencies", "").split(", "), name
        else:
            assert meta.get("Category") == CATEGORY, name
            for loc in ASIAN:
                assert CJK.search(meta.get(f"Category-{loc}", "")), (name, loc)
            for loc in LATIN:
                category = meta.get(f"Category-{loc}", "")
                assert category.startswith(("Bastian's", "Suite")), (name, loc)
    categories = {tuple(meta.get(f"Category-{loc}") for loc in ASIAN) for n, meta in tocs.items()}
    assert len(categories - {(None, None, None)}) == 1  # one header in every language
    children = {meta["Group"] for meta in tocs.values() if "Group" in meta}
    assert children == {"Bastians_Data", "Bastians_Map"}
    assert all(meta.get("Group") == "Bastians_Data" for n, meta in tocs.items() if "_Data_" in n)
    assert len(apps) <= 15  # the rows a player sees with the header unfolded


def test_every_addon_speaks_korean_and_chinese_in_the_list():
    for name, meta in shipped().items():
        for loc in ASIAN:
            assert CJK.search(meta.get(f"Notes-{loc}", "")), (name, loc)
            title = meta.get(f"Title-{loc}")
            if title is not None:
                assert title.startswith("Bastian's "), (name, loc)  # the names stay the suite's
        assert meta.get("Notes-zhCN") != meta.get("Notes-zhTW"), name  # Taiwan's own text


def test_every_addon_speaks_german_french_and_spanish_in_the_list():
    for name, meta in shipped().items():
        notes = [meta.get(f"Notes-{loc}", "") for loc in LATIN]
        assert all(notes) and len(set(notes[:3])) == 3, name  # three languages of their own
        assert meta["Notes-esMX"] == meta["Notes-esES"], name  # one Spanish
        assert notes[0] != meta["Notes"], name
        for loc in LATIN:
            title = meta.get(f"Title-{loc}")
            assert (title is None) == (meta.get("Title-koKR") is None), (name, loc)
            if title is not None:
                assert title.startswith("Bastian's "), (name, loc)
