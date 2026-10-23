"""Tests for tools/install.py. Everything happens inside tmp_path."""

import install
import pytest


@pytest.fixture
def world(tmp_path):
    addons = tmp_path / "repo" / "addons"
    for name in ("Bastians_Core", "Bastians_Data"):
        (addons / name).mkdir(parents=True)
        (addons / name / f"{name}.toc").write_text("## Interface: 16001\n", encoding="utf-8")
    client = tmp_path / "wow" / "_retail_"
    dest = client / "Interface" / "AddOns"
    dest.mkdir(parents=True)
    return addons, client, dest


def test_install_creates_links_and_is_idempotent(world):
    addons, _, dest = world
    first = install.install(addons, dest)
    assert all(line.startswith("linked") for line in first)
    assert (dest / "Bastians_Core" / "Bastians_Core.toc").is_file()
    second = install.install(addons, dest)
    assert all(line.startswith("ok") for line in second)


def test_edits_show_through_link(world):
    addons, _, dest = world
    install.install(addons, dest)
    (addons / "Bastians_Core" / "New.lua").write_text("-- x\n", encoding="utf-8")
    assert (dest / "Bastians_Core" / "New.lua").is_file()


def test_link_elsewhere_is_replaced(world, tmp_path):
    addons, _, dest = world
    other = tmp_path / "other"
    other.mkdir()
    install.make_link(dest / "Bastians_Core", other)
    report = install.install(addons, dest)
    assert any(line.startswith("replaced") for line in report)
    assert install.link_target(dest / "Bastians_Core") == (addons / "Bastians_Core").resolve()
    assert other.is_dir()


def test_real_folder_is_refused(world):
    addons, _, dest = world
    (dest / "Bastians_Core").mkdir()
    (dest / "Bastians_Core" / "keep.txt").write_text("mine", encoding="utf-8")
    report = install.install(addons, dest)
    assert any(line.startswith("REFUSED") for line in report)
    assert (dest / "Bastians_Core" / "keep.txt").is_file()
    assert install.is_link(dest / "Bastians_Data")


def test_remove_only_removes_our_links(world, tmp_path):
    addons, _, dest = world
    install.install(addons, dest)
    other = tmp_path / "other"
    other.mkdir()
    install.remove_link(dest / "Bastians_Data")
    install.make_link(dest / "Bastians_Data", other)
    report = install.remove(addons, dest)
    assert "removed  Bastians_Core" in report
    assert any(line.startswith("skipped  Bastians_Data") for line in report)
    assert not (dest / "Bastians_Core").exists()
    assert install.is_link(dest / "Bastians_Data")
    assert (addons / "Bastians_Core" / "Bastians_Core.toc").is_file()


def test_remove_leaves_real_folders(world):
    addons, _, dest = world
    (dest / "Bastians_Core").mkdir()
    report = install.remove(addons, dest)
    assert any(line.startswith("skipped  Bastians_Core") for line in report)
    assert (dest / "Bastians_Core").is_dir()


def test_list(world):
    addons, _, dest = world
    install.make_link(dest / "Bastians_Core", addons / "Bastians_Core")
    lines = install.list_links(addons, dest)
    assert lines[0].startswith("Bastians_Core: linked ->")
    assert lines[1] == "Bastians_Data: not installed"


def test_config_remembers_client_folder(world, tmp_path):
    _, client, _ = world
    config = tmp_path / ".local" / "install.toml"
    assert install.resolve_client_dir("retail", str(client), config) == client.resolve()
    assert install.resolve_client_dir("retail", None, config) == client.resolve()
    assert install.load_config(config) == {"retail": str(client.resolve())}


def test_unknown_client_folder_is_an_error(tmp_path):
    with pytest.raises(install.InstallError, match="--wow"):
        install.resolve_client_dir("forever", None, tmp_path / "install.toml")


def test_wow_folder_without_interface_is_an_error(tmp_path):
    with pytest.raises(install.InstallError, match="Interface"):
        install.resolve_client_dir("forever", str(tmp_path), tmp_path / "install.toml")
