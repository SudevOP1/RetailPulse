"""Download the 9 Olist CSVs into data/raw/.

Tries the Kaggle API first (needs ~/.kaggle/kaggle.json or ~/.kaggle/access_token),
then falls back to the public GitHub mirror (no token needed). Idempotent: files
that already exist are skipped, so re-running is cheap.

Usage:
    python scripts/download_data.py            # download what's missing
    python scripts/download_data.py --source github
    python scripts/download_data.py --force    # re-download everything
"""

from __future__ import annotations

import argparse
import codecs
import os
import sys
from pathlib import Path

import requests

ROOT = Path(__file__).resolve().parents[1]
RAW_DIR = ROOT / "data" / "raw"

KAGGLE_REF = "olistbr/brazilian-ecommerce"
GITHUB_BASE = "https://raw.githubusercontent.com/olist/work-at-olist-data/master/datasets"

FILES = [
    "olist_customers_dataset.csv",
    "olist_geolocation_dataset.csv",
    "olist_order_items_dataset.csv",
    "olist_order_payments_dataset.csv",
    "olist_order_reviews_dataset.csv",
    "olist_orders_dataset.csv",
    "olist_products_dataset.csv",
    "olist_sellers_dataset.csv",
    "product_category_name_translation.csv",
]


def missing_files(force: bool = False) -> list[str]:
    return [f for f in FILES if force or not (RAW_DIR / f).exists()]


def _load_kaggle_token() -> None:
    """Expose ~/.kaggle/access_token as KAGGLE_API_TOKEN, tolerating UTF-16/BOM files.

    PowerShell's `>` writes UTF-16 with a BOM, which the Kaggle client sends verbatim
    in the auth header and fails. Decoding here makes either encoding work.
    """
    if os.getenv("KAGGLE_API_TOKEN"):
        return
    token_file = Path.home() / ".kaggle" / "access_token"
    if not token_file.exists():
        return
    raw = token_file.read_bytes()
    encoding = "utf-16" if raw.startswith((codecs.BOM_UTF16_LE, codecs.BOM_UTF16_BE)) else "utf-8-sig"
    token = raw.decode(encoding).strip()
    if token:
        os.environ["KAGGLE_API_TOKEN"] = token


def download_kaggle() -> bool:
    """Download the whole dataset via the Kaggle API. Returns True on success."""
    try:
        _load_kaggle_token()
        from kaggle.api.kaggle_api_extended import KaggleApi

        api = KaggleApi()
        api.authenticate()
        print(f"[kaggle] downloading {KAGGLE_REF} -> {RAW_DIR}")
        api.dataset_download_files(KAGGLE_REF, path=str(RAW_DIR), unzip=True, quiet=False)
    except Exception as exc:  # auth missing, network, API change: all mean "fall back"
        # Only the type: messages from auth errors can echo the token.
        print(f"[kaggle] failed ({type(exc).__name__}); falling back to GitHub")
        return False
    return not missing_files()


def download_github(files: list[str]) -> None:
    for name in files:
        url = f"{GITHUB_BASE}/{name}"
        dest = RAW_DIR / name
        tmp = dest.with_suffix(".part")
        print(f"[github] {name}")
        with requests.get(url, stream=True, timeout=120) as r:
            r.raise_for_status()
            with tmp.open("wb") as fh:
                for chunk in r.iter_content(chunk_size=1 << 20):
                    fh.write(chunk)
        tmp.replace(dest)  # atomic: a half-downloaded file never looks "present"


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--source", choices=["auto", "kaggle", "github"], default="auto")
    parser.add_argument("--force", action="store_true", help="re-download files that already exist")
    args = parser.parse_args()

    RAW_DIR.mkdir(parents=True, exist_ok=True)
    todo = missing_files(args.force)
    if not todo:
        print(f"All {len(FILES)} files already in {RAW_DIR}; nothing to do.")
        return 0

    # Existing files are only overwritten by a successful download, never deleted up front.
    if args.source in ("auto", "kaggle") and download_kaggle():
        pass
    elif args.source == "kaggle":
        return 1
    else:
        download_github(missing_files(args.force))

    still_missing = missing_files()
    if still_missing:
        print(f"ERROR: still missing {still_missing}", file=sys.stderr)
        return 1
    for f in FILES:
        print(f"  {f:45s} {(RAW_DIR / f).stat().st_size / 1e6:8.1f} MB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
