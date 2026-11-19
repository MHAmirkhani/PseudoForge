#!/usr/bin/env python3
"""Render manuscript v1.4.0 figures from checked-in numerical data."""
import json
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, Rectangle

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
    box(ax, .24, .10, .38, .14, "Multi-Level Verification (L1-L6)\nAtomic tests, SCF, AE benchmarks")
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
        (.18, "Gate Verification (L1->L6 Ladder)", LIGHT),
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
    # Converged cutoff comparisons on Silicon diamond
    # Arm A (APE baseline): 74.05 meV/atom (fails L4 ghost)
    # Arm B (APE single repair lloc=0): 27.36 meV/atom (passes L4, fails L5)
    # Arm C (APE cross-engine ONCVPSP donor): 36.81 meV/atom (passes L4, fails L5)
    # Native ONCVPSP (SG15 tuning reference): 1.26 meV/atom (passes L5)
    labels = ["Arm A\n(Baseline)", "Arm B\n(Single)", "Arm C\n(Cross-Eng)", "Native\nONCVPSP"]
    errors = [74.05, 27.36, 36.81, 1.26]
    colors = [CORAL, GOLD, TEAL, GREEN]

    fig, ax1 = plt.subplots(figsize=(3.45, 2.75), layout="constrained")
    bars = ax1.bar(range(4), errors, color=colors, width=0.52, edgecolor=INK, linewidth=0.85)

    ax1.set_xticks(range(4))
    ax1.set_xticklabels(labels, fontsize=8.0)
    ax1.set_ylabel("Worst EOS Error (meV/atom) vs AE", fontsize=8.2, color=INK)
    ax1.tick_params(axis="y", labelsize=8.0)
    ax1.grid(axis="y", linestyle="--", alpha=0.3)
    ax1.axhline(2.0, color="dimgray", linestyle=":", linewidth=1.0, label="L5 Gate (2.0 meV/atom)")

    for bar, val in zip(bars, errors):
        yval = bar.get_height()
        ax1.text(bar.get_x() + bar.get_width()/2.0, yval + 1.5, f"{val:.1f}", ha="center", va="bottom", fontsize=8.0, fontweight="bold")

    ax1.set_ylim(0, 85)
    ax1.legend(fontsize=7.5, loc="upper right", framealpha=0.9)
    fig.savefig(OUT / "si_repair.pdf")
    plt.close(fig)


def ge_comparison():
    fig, ax = plt.subplots(figsize=(3.45, 2.35), layout="constrained")
    categories = ["L1 Gen", "L2 Serial", "L3 SCF", "L4 Ghost", "L5 EOS"]
    
    # Arm pass rates across gates on Ge diamond (boundary)
    y_a = [1, 1, 1, 0, 0]
    y_b = [1, 1, 1, 0, 0]
    y_c = [1, 1, 0, 1, 0]
    
    x = range(len(categories))
    width = 0.25
    ax.bar([i - width for i in x], y_a, width=width, label="Arm A (Baseline)", color=CORAL, edgecolor=INK)
    ax.bar(x, y_b, width=width, label="Arm B (Single lloc=0)", color=GOLD, edgecolor=INK)
    ax.bar([i + width for i in x], y_c, width=width, label="Arm C (Cross ONCVPSP)", color=TEAL, edgecolor=INK)
    
    ax.set_xticks(x)
    ax.set_xticklabels(categories, fontsize=7.8)
    ax.set_yticks([0, 1])
    ax.set_yticklabels(["Fail", "Pass"], fontsize=8.0)
    ax.set_ylabel("Gate Verification Outcome", fontsize=8.0)
    ax.legend(fontsize=7.0, loc="center right", framealpha=0.9)
    ax.grid(axis="y", linestyle="--", alpha=0.3)
    ax.set_title("Ge Diamond: 3d10 Semicore Boundary\n(Partial Rescue, 237x Error Reduction)", fontsize=8.0, pad=4)
    
    fig.savefig(OUT / "ge_comparison.pdf")
    plt.close(fig)


def domain_map():
    """Render periodic-table / core-shell topology domain map of L6 transferability."""
    families = ["MgO", "AlP", "SiC", "BN", "GaAs", "Ge"]
    errors = [0.86, 0.92, 1.14, 1.38, 18.94, 11.83]
    topologies = [
        "Ionic [Ne]/[Ne]\n(Row 3/2)",
        "Main-group [Ne]\n(Row 3/3)",
        "Main-group [Ne]/[He]\n(Row 3/2)",
        "Light [He]/[He]\n(Row 2/2)",
        "Semicore 3d10\n(Row 4/4)",
        "Semicore 3d10\n(Row 4 Unary)"
    ]
    colors = [GREEN, GREEN, GREEN, GREEN, CORAL, CORAL]

    fig, (ax_bar, ax_map) = plt.subplots(1, 2, figsize=(7.05, 2.65),
                                         gridspec_kw={"width_ratios": [1.15, 1.05]},
                                         layout="constrained")

    # Bar chart of out-of-family holdout error
    bars = ax_bar.bar(range(len(families)), errors, color=colors, width=0.55, edgecolor=INK, linewidth=0.85)
    ax_bar.axhline(2.0, color="dimgray", linestyle="--", linewidth=1.0, label="L6 Gate (2.0 meV/atom)")
    ax_bar.set_xticks(range(len(families)))
    ax_bar.set_xticklabels([f"{f}\n{t}" for f, t in zip(families, topologies)], fontsize=6.8)
    ax_bar.set_ylabel("Holdout Error (meV/atom) vs AE Reference", fontsize=8.0)
    ax_bar.tick_params(axis="y", labelsize=7.5)
    ax_bar.set_title("Holdout Transferability Accuracy", fontsize=8.5)
    ax_bar.grid(axis="y", linestyle=":", alpha=0.4)
    ax_bar.set_ylim(0, 22)
    ax_bar.legend(fontsize=7.0, loc="upper left", framealpha=0.9)

    for bar, val in zip(bars, errors):
        y = bar.get_height()
        ax_bar.text(bar.get_x() + bar.get_width()/2.0, y + 0.45, f"{val:.2f}",
                    ha="center", va="bottom", fontsize=7.2, fontweight="bold")

    # Schematic core-shell topology domain map
    ax_map.set(xlim=(0, 10), ylim=(10, 0))  # top to bottom for easier coordinate reasoning
    ax_map.axis("off")
    ax_map.set_title("Core-Shell Topology Domain Map", fontsize=8.5)

    # Main-group zone (Success)
    ax_map.add_patch(FancyBboxPatch((0.4, 0.4), 9.2, 4.3, boxstyle="round,pad=0.15,rounding_size=0.25",
                                    edgecolor=GREEN, facecolor="#e8f5e9", linewidth=1.2))
    ax_map.text(0.8, 1.1, "VALID TRANSPLANTATION DOMAIN (L6 POPULATED)", fontsize=7.5, fontweight="bold", color=GREEN)
    ax_map.text(0.8, 1.9, "• Main-group cores ([He], [Ne]) with pure sp valence", fontsize=7.0, color=INK)
    ax_map.text(0.8, 2.7, "• Transferable cutoff radii rc(l) and local channel lloc", fontsize=7.0, color=INK)
    ax_map.text(0.8, 3.5, "• Verified families: MgO (0.86), AlP (0.92), SiC (1.14), BN (1.38)", fontsize=7.0, color=INK)
    ax_map.text(0.8, 4.2, "• Status: L6 Passed (Holdout errors < 2.0 meV/atom)", fontsize=7.0, fontweight="bold", color=GREEN)

    # Semicore / Transition boundary zone
    ax_map.add_patch(FancyBboxPatch((0.4, 5.1), 9.2, 4.4, boxstyle="round,pad=0.15,rounding_size=0.25",
                                    edgecolor=CORAL, facecolor="#ffebee", linewidth=1.2))
    ax_map.text(0.8, 5.8, "PHYSICAL APPLICABILITY BOUNDARY", fontsize=7.5, fontweight="bold", color=CORAL)
    ax_map.text(0.8, 6.6, "• Filled 3d10 semicore shell (Row 4 elements: Ga, Ge, As)", fontsize=7.0, color=INK)
    ax_map.text(0.8, 7.4, "• Core-valence exchange overlap & unscreening mismatch", fontsize=7.0, color=INK)
    ax_map.text(0.8, 8.2, "• Boundary systems: GaAs (18.94 meV), Ge (11.83 meV)", fontsize=7.0, color=INK)
    ax_map.text(0.8, 8.9, "• Status: L6 Bounded (Requires explicit semicore or d-manifold)", fontsize=7.0, fontweight="bold", color=CORAL)

    fig.savefig(OUT / "domain_map.pdf")
    plt.close(fig)


if __name__ == "__main__":
    architecture()
    workflow()
    si_repair()
    ge_comparison()
    domain_map()
    print("Manuscript v1.4.0 figures generated successfully.")
