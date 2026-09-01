# CredResolve-Analytics-Project
Collections data analysis using SQL and Python to evaluate recovery performance and data quality.
<<<<<<< HEAD
# CRED-RESOLVE_ANALYTICS_PROJECT
Forensic data analysis of a fintech collections claim ("recovery up 11% MoM"), Found it was one lucky month not a trend. Includes cleaning pipeline, SQL, Stats Notebook, Dashboard, and ROI memo
=======
# Collections Analytics — Project README

Answers the assignment brief: is the reported "recovery improved 11% month-on-month"
claim real, and where should the ₹10 Cr go. Short version: **the 11% is one
cherry-picked month inside a flat, statistically flat trend (p = 0.89)** — full
reasoning is in the notebook and memo below.

See `submission_deliverable_map.png` for a one-glance visual of this same table.

## Where to find everything

| # | Folder | What it is | Start here |
|---|---|---|---|
| 1 | `1_golden_dataset/` | The cleaned, trustworthy dataset + the SQL that builds it | `docs/01_golden_dataset_documentation.md` |
| 2 | `2_data_quality_report/` | The forensic findings — duplicate payments, attribution errors, timezone bugs, agent identity issues, etc. | `02_data_quality_report.md` |
| 3 | `3_sql_repository/` | All SQL, organized and runnable end to end | `README.md` inside the folder |
| 4 | `4_analysis_notebook/` | The actual analysis — what happened, why, is the 11% real, counterfactual design | `analysis_notebook.ipynb` |
| 5 | `5_executive_dashboard/` | One-screen visual summary | `executive_dashboard.html` — open in any browser |
| 6 | `6_executive_memo/` | 2-page recommendation memo | `executive_memo.docx` |
| 7 | `7_architecture_diagram/` | How this becomes a production system | `architecture_diagram.svg` + `03_production_design.md` |

## How to run any of it yourself

You need `raw/` (the 17 source CSVs from the original dataset zip) sitting next to
whichever folder you're running from.

```bash
pip install duckdb pandas --break-system-packages

# rebuild the golden dataset from scratch
cd 1_golden_dataset
python3 run_pipeline.py

# or run the full organized SQL repo (staging -> golden -> metrics -> analysis)
cd 3_sql_repository
python3 run_all.py
```

The notebook (`4_analysis_notebook/analysis_notebook.ipynb`) already has all cells
executed with real output, so you can just read it — but if you want to re-run it,
it needs `collections.duckdb` (included in that folder) or a rebuilt one from step
above sitting alongside it.

The dashboard (`5_executive_dashboard/executive_dashboard.html`) and the memo
(`6_executive_memo/executive_memo.docx`) are standalone — just open them.

## Reading order, if you're reviewing this end to end

1. `2_data_quality_report/02_data_quality_report.md` — the problems found in the raw data
2. `1_golden_dataset/docs/01_golden_dataset_documentation.md` — how those problems were fixed
3. `4_analysis_notebook/analysis_notebook.ipynb` — the actual analysis and the 11% verdict
4. `5_executive_dashboard/executive_dashboard.html` — the 60-second version
5. `6_executive_memo/executive_memo.docx` — the recommendation
6. `7_architecture_diagram/` — how this runs in production, going forward

## What's not included

A hosted **Git repository** — this folder is structured so you can `git init` it
directly and push, but I can't create a remote repo on your behalf.
>>>>>>> dbd6c8a (Collections analytics assignment - golden dataset, SQL, notebook, dashboard, memo, architecture)
