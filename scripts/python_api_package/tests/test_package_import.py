from __future__ import annotations

from importlib.metadata import version


def test_package_is_importable():
    import hiveio_hivemind_api  # noqa: F401


def test_version_is_not_placeholder():
    pkg_version = version("hiveio-hivemind-api")

    assert pkg_version != "0.0.0", f"Version should be set by poetry-dynamic-versioning, got: {pkg_version}"
