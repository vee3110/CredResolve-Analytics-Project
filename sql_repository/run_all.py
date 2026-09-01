import duckdb
import glob
import os

DB_PATH = "collections.duckdb"
if os.path.exists(DB_PATH):
    os.remove(DB_PATH)

con = duckdb.connect(DB_PATH)

folders = ["01_staging", "02_golden", "03_metrics", "04_analysis"]
for folder in folders:
    files = sorted(glob.glob(f"{folder}/*.sql"))
    for f in files:
        print("=" * 80)
        print("RUNNING:", f)
        with open(f) as fh:
            script = fh.read()
        result = con.execute(script)
        try:
            df = result.fetchdf()
            if len(df):
                print(df.to_string(index=False))
        except Exception:
            pass

print("=" * 80)
print("PIPELINE COMPLETE. Tables and views available:")
objs = con.execute("""
    SELECT table_name, table_type FROM information_schema.tables
    WHERE table_schema='main' ORDER BY table_type, table_name
""").fetchdf()
print(objs.to_string(index=False))
con.close()
