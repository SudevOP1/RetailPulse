"""One Matplotlib/Seaborn style for every memo-ready chart (notebooks 01 and 02).

    from scripts.plot_style import apply_style, BLUE, ORANGE, save_fig
"""

from __future__ import annotations

from pathlib import Path

import matplotlib.pyplot as plt
import seaborn as sns

ROOT = Path(__file__).resolve().parents[1]
IMG_DIR = ROOT / "docs" / "img"

# Categorical slots 1-2 of a CVD-validated palette; on time / reference = blue, late = orange.
BLUE = "#2a78d6"
ORANGE = "#eb6834"
GREY = "#a9a8a2"  # context (out-of-window months, "other")
INK = "#0b0b0b"
INK_2 = "#52514e"
SURFACE = "#fcfcfb"


def apply_style() -> None:
    sns.set_theme(style="whitegrid", context="notebook")
    plt.rcParams.update(
        {
            "figure.facecolor": SURFACE,
            "axes.facecolor": SURFACE,
            "savefig.facecolor": SURFACE,
            "axes.edgecolor": "#d8d7d2",
            "axes.labelcolor": INK_2,
            "axes.titlecolor": INK,
            "axes.titlesize": 13,
            "axes.titleweight": "bold",
            "axes.titlelocation": "left",
            "axes.spines.top": False,
            "axes.spines.right": False,
            "grid.color": "#ebeae6",
            "grid.linewidth": 0.8,
            "xtick.color": INK_2,
            "ytick.color": INK_2,
            "lines.linewidth": 2,
            "legend.frameon": False,
            "savefig.dpi": 160,
            "savefig.bbox": "tight",
        }
    )


def save_fig(fig: plt.Figure, name: str) -> Path:
    """Save to docs/img/<name>.png and return the path."""
    IMG_DIR.mkdir(parents=True, exist_ok=True)
    path = IMG_DIR / f"{name}.png"
    fig.savefig(path)
    return path
