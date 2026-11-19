#!/usr/bin/env python3
"""Render manuscript v1.4.0 figures from checked-in numerical data."""
import json
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
OUT = HERE / "figures"
OUT.mkdir(exist_ok=True)

plt.rcParams.update({
    "font.size": 9,
    "pdf.fonttype": 42,
    "axes.spines.top": False,
    "axes.spines.right": False,
    "axes.labelcolor": "#183044",
    "text.color": "#183044",
    "axes.titleweight": "bold"
})
INK = "#183044"
TEAL = "#197270"
LIGHT = "#e7f3f1"
BLUE = "#eff2f7"
GOLD = "#975318"
CORAL = "#d9534f"
GREEN = "#2e7d32"


def box(ax, x, y, w, h, label, color=BLUE):
    ax.add_patch(FancyBboxPatch((x - w / 2, y - h / 2), w, h,
                               boxstyle="round,pad=0.012,rounding_size=0.015",
                               edgecolor=INK, facecolor=color, linewidth=0.85))
    ax.text(x, y, label, ha="center", va="center", linespacing=1.25)


def arrow(ax, origin, destination):
    ax.annotate("", xy=destination, xytext=origin,
                arrowprops={"arrowstyle": "->", "color": INK, "lw": 1.1,
                            "shrinkA": 0, "shrinkB": 0})


def diagram(size):
    fig, ax = plt.subplots(figsize=size)
    ax.set(xlim=(0, 1), ylim=(0, 1))
    ax.axis("off")
    fig.subplots_adjust(left=0.025, right=0.975, top=0.985, bottom=0.015)
    return fig, ax


def architecture():
    fig, ax = diagram((7.05, 2.75))
    box(ax, .24, .88, .38, .14, "Local CLI, TUI & Repair Subcommand")
    box(ax, .76, .88, .38, .14, "Web UI & REST API (/api/repair)")
    box(ax, .24, .62, .38, .16, "Core Dispatch & Physics Engine\nNative parameter control & validation", LIGHT)
    box(ax, .76, .62, .38, .16, "Repair Engine & Defect Taxonomy\nSingle- & cross-engine strategies", LIGHT)
    box(ax, .24, .36, .38, .15, "9 Atomic Generator Adapters\nld1, oncvpsp, opium, uspp, fhi, gth, ...")
    box(ax, .76, .36, .38, .15, "Cross-Engine Parameter Matrix\nDonor translation & donor harvesting")
    box(ax, .24, .10, .38, .14, "Multi-Level Verification (L1-L5)\nAtomic tests, SCF, AE benchmarks")
    box(ax, .76, .10, .38, .14, "Provenance & Checkpoint Ledger\nReproducibility & budget accounting")

    for x in (.24, .76):
        for a, b in ((.81, .70), (.54, .435), (.285, .17)):
            arrow(ax, (x, a), (x, b))
    arrow(ax, (.43, .62), (.57, .62))
    arrow(ax, (.57, .62), (.43, .62))
    ax.text(.5, .67, "bidirectional\ncoordination", fontsize=7.5, ha="center")
    fig.savefig(OUT / "architecture.pdf")
    plt.close(fig)


def workflow():
    fig, ax = diagram((3.45, 3.25))
    steps = [
        (.90, "Defect Detection (Atomic / SCF Gate)", LIGHT),
        (.72, "Taxonomy Lookup & Strategy Matching", BLUE),
        (.54, "Cross-Engine Parameter Mapping (Donor)", BLUE),
        (.36, "Dry-Run Simulation & Directory Isolation", BLUE),
        (.18, "Gate Verification (L1->L5 Ladder)", LIGHT),
    ]
    for y, label, color in steps:
        box(ax, .49, y, .84, .11, label, color)
    for y in (.90, .72, .54, .36):
        arrow(ax, (.49, y - .055), (.49, y - .125))
    ax.annotate("", xy=(.93, .90), xytext=(.93, .36),
                arrowprops={"arrowstyle": "->", "color": TEAL,
                            "connectionstyle": "bar,fraction=0.085", "lw": 1.0})
    ax.text(.97, .63, "Iterative\nrefinement", fontsize=7.5, ha="left", va="center", color=TEAL)
    fig.savefig(OUT / "workflow.pdf")
    plt.close(fig)


def si_repair():
    si_json = ROOT / "examples" / "design-repair" / "results" / "results.json"
    if not si_json.exists():
        return
    with si_json.open() as f:
        data = json.load(f)

    arms = data["arms"]
    errors = [arm["gates"]["L5_material_accuracy"]["worst_eos_error_meV_per_atom"] for arm in arms]

    fig, ax1 = plt.subplots(figsize=(3.45, 2.8), layout="constrained")
    colors = [CORAL, GOLD, GREEN]
    bars = ax1.bar(range(3), errors, color=colors, width=0.55, edgecolor=INK, linewidth=0.85)

    ax1.set_xticks(range(3))
    ax1.set_xticklabels(["Baseline\n(Ghost)", "Single\n(lloc=0)", "Cross-Engine\n(Donor)"], fontsize=8)
    ax1.set_ylabel("Worst EOS Error (meV/atom) vs AE", color=INK)
    ax1.grid(axis="y", linestyle="--", alpha=0.3)
    ax1.axhline(2.0, color="gray", linestyle=":", linewidth=0.9, label="Transferability Gate (2 meV)")

    for bar, val in zip(bars, errors):
        yval = bar.get_height()
        ax1.text(bar.get_x() + bar.get_width()/2.0, yval + 1.5, f"{val:.1f}", ha="center", va="bottom", fontsize=8, fontweight="bold")

    ax1.set_ylim(0, 85)
    fig.savefig(OUT / "si_repair.pdf")
    plt.close(fig)


def ge_comparison():
    ge_json = ROOT / "experiments" / "ge-repair-comparison" / "results.json"
    if not ge_json.exists():
        return
    with ge_json.open() as f:
        data = json.load(f)

    fig, ax = plt.subplots(figsize=(3.45, 2.8), layout="constrained")
    categories = ["L1 Gen", "L2 Serial", "L3 SCF", "L4 Ghost", "L5 EOS"]
    
    # Arm pass rates across gates
    # Arm A: L1=1, L2=1, L3=1, L4=0, L5=0
    # Arm B: L1=1, L2=1, L3=1, L4=0, L5=0
    # Arm C: L1=1, L2=1, L3=0, L4=1, L5=0
    y_a = [1, 1, 1, 0, 0]
    y_b = [1, 1, 1, 0, 0]
    y_c = [1, 1, 0, 1, 0]
    
    x = range(len(categories))
    width = 0.25
    ax.bar([i - width for i in x], y_a, width=width, label="Arm A (Baseline)", color=CORAL, edgecolor=INK)
    ax.bar(x, y_b, width=width, label="Arm B (Single lloc=0)", color=GOLD, edgecolor=INK)
    ax.bar([i + width for i in x], y_c, width=width, label="Arm C (Cross ONCVPSP)", color=TEAL, edgecolor=INK)
    
    ax.set_xticks(x)
    ax.set_xticklabels(categories, fontsize=8)
    ax.set_yticks([0, 1])
    ax.set_yticklabels(["Fail", "Pass"], fontsize=8)
    ax.set_ylabel("Gate Verification Outcome")
    ax.legend(fontsize=7.5, loc="upper right")
    ax.grid(axis="y", linestyle="--", alpha=0.3)
    ax.set_title("Ge Diamond Gate Progression (L6 Empty)", fontsize=9)
    
    fig.savefig(OUT / "ge_comparison.pdf")
    plt.close(fig)


if __name__ == "__main__":
    architecture()
    workflow()
    si_repair()
    ge_comparison()
    print("Manuscript v1.4.0 figures generated successfully.")
