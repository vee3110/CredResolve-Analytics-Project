import duckdb
import glob
import os

DB_PATH = "collections.duckdb"
if os.path.exists(DB_PATH):
    os.remove(DB_PATH)

con = duckdb.connect(DB_PATH)

sql_files = sorted(glob.glob("sql/*.sql"))
for f in sql_files:
    print("=" * 80)
    print("RUNNING:", f)
    with open(f) as fh:
        script = fh.read()
    # duckdb python execute() runs one statement; use a loose split on ';\n' is risky with
    # comments, so we rely on duckdb's own multi-statement execution via `execute` per stmt
    # duckdb's `sql()`/`execute()` handles multiple statements in one string fine.
    try:
        result = con.execute(script)
        try:
            df = result.fetchdf()
            print(df.to_string(index=False))
        except Exception:
            pass
    except Exception as e:
        print("ERROR in", f, ":", e)
        raise

# Export every golden_* table to CSV
os.makedirs("golden", exist_ok=True)
tables = con.execute("SELECT table_name FROM information_schema.tables WHERE table_name LIKE 'golden_%'").fetchall()
print("=" * 80)
print("EXPORTING GOLDEN TABLES")
for (t,) in tables:
    out_path = f"golden/{t}.csv"
    con.execute(f"COPY {t} TO '{out_path}' (HEADER, DELIMITER ',')")
    n = con.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0]
    print(f"  {t}: {n} rows -> {out_path}")

con.close()
print("DONE")
