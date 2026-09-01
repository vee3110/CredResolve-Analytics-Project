import pandas as pd
import os, glob

RAW = "raw"
files = sorted(glob.glob(os.path.join(RAW, "*.csv")))
files = [f for f in files if "data_dictionary" not in f]

pd.set_option("display.width", 160)
pd.set_option("display.max_columns", 50)

summary_rows = []

for f in files:
    name = os.path.basename(f).replace(".csv", "")
    df = pd.read_csv(f, low_memory=False)
    n_rows = len(df)
    n_cols = df.shape[1]
    dupe_rows = df.duplicated().sum()

    # guess a primary key col: <name-singular>_id or first *_id column
    id_cols = [c for c in df.columns if c.endswith("_id")]
    pk_guess = id_cols[0] if id_cols else None
    pk_dupes = None
    if pk_guess:
        pk_dupes = df[pk_guess].duplicated().sum()

    null_pct = (df.isna().mean() * 100).round(2)
    top_nulls = null_pct[null_pct > 0].sort_values(ascending=False).head(5)

    date_cols = [c for c in df.columns if "_at" in c or "date" in c]
    date_range = {}
    for dc in date_cols:
        try:
            parsed = pd.to_datetime(df[dc], errors="coerce", utc=False)
            date_range[dc] = (parsed.min(), parsed.max(), parsed.isna().sum())
        except Exception as e:
            date_range[dc] = ("ERR", str(e), None)

    print("=" * 100)
    print(f"TABLE: {name}  | rows={n_rows} cols={n_cols} | full-row dupes={dupe_rows}")
    print(f"columns: {list(df.columns)}")
    if pk_guess:
        print(f"guessed PK '{pk_guess}': {df[pk_guess].nunique()} unique vs {n_rows} rows -> {pk_dupes} duplicate PK values")
    if len(top_nulls):
        print("top null% columns:")
        print(top_nulls.to_string())
    if date_range:
        print("date columns (min, max, n_nat):")
        for k, v in date_range.items():
            print(f"  {k}: {v}")

    summary_rows.append({
        "table": name, "rows": n_rows, "cols": n_cols,
        "full_row_dupes": dupe_rows,
        "pk_guess": pk_guess,
        "pk_unique": df[pk_guess].nunique() if pk_guess else None,
        "pk_dupes": pk_dupes,
    })

print("=" * 100)
summary = pd.DataFrame(summary_rows)
print(summary.to_string(index=False))
summary.to_csv("profile_summary.csv", index=False)
