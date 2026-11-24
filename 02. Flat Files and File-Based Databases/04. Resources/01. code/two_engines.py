# IT 505 · Class 2 · Lesson 2 · Two embedded engines, one export: SQLite for the stall tablet, DuckDB for the Monday report.
# Import the csv module to read the export, and the os module to look at files on the disk.
import csv
# The os module gives access to file operations such as exists, remove and getsize.
import os
# Import sqlite3: the SQLite engine is a library that ships inside Python's standard library.
import sqlite3
# Import duckdb: the DuckDB engine is a library installed with the command "pip install duckdb".
import duckdb
# Start from a clean state: list the two database files this script creates.
for name in ("stall.sqlite", "mercadillo.duckdb"):
    # If a file with that name is left from an earlier run ...
    if os.path.exists(name):
        # ... delete it, so that every run begins with empty databases.
        os.remove(name)
# PART A - SQLite on the stall tablet. Connecting to a file name that does not exist creates the file: no server, no port, no password.
lite = sqlite3.connect("stall.sqlite")
# Create a table with four declared columns; SQLite writes the values of each row next to each other (a row store).
lite.execute("CREATE TABLE sales (order_id TEXT, product TEXT, unit_price REAL, quantity INTEGER)")
# Open the export as UTF-8 text; newline="" lets the csv module handle line endings itself.
with open("m505_excerpt.csv", encoding="utf-8", newline="") as f:
    # DictReader turns every line into a dictionary whose keys are the names in the header.
    for row in csv.DictReader(f):
        # A malformed line has an extra value, which DictReader stores under the key None: skip that line.
        if None in row:
            # continue jumps straight to the next line of the file.
            continue
        # Insert one sale, as the tablet does after each customer; the ? placeholders receive the four values safely.
        lite.execute("INSERT INTO sales VALUES (?, ?, ?, ?)", (row["order_id"], row["product"], row["unit_price"], row["quantity"] or None))
        # Commit after every sale: each sale is its own small transaction, written to the file immediately.
        lite.commit()
# Count the rows that reached the SQLite file.
print("A1. Rows in stall.sqlite:", lite.execute("SELECT count(*) FROM sales").fetchone()[0])
# Read one order back by its identifier: the typical small read that an application performs many times a day.
print("A2. Order M505-1044:", lite.execute("SELECT product, quantity FROM sales WHERE order_id = 'M505-1044'").fetchall())
# Type affinity: SQLite accepts the text 'two' in a column declared INTEGER instead of refusing it.
lite.execute("INSERT INTO sales VALUES ('TEST', 'test row', 1.0, 'two')")
# The function typeof() reveals the type of the value that was really stored.
print("A3. SQLite stored 'two' in an INTEGER column as:", lite.execute("SELECT typeof(quantity) FROM sales WHERE order_id = 'TEST'").fetchone()[0])
# Remove the test row again, so that only real sales stay in the table.
lite.execute("DELETE FROM sales WHERE order_id = 'TEST'")
# Commit the deletion and close the connection; the database file stays on the disk.
lite.commit()
# Closing releases the file; nothing keeps running in the background, because there is no server.
lite.close()
# PART B - DuckDB for the Monday report. Connecting to a new file name creates mercadillo.duckdb: again one file, no server.
duck = duckdb.connect("mercadillo.duckdb")
# First attempt: query the CSV file where it lies and let the CSV sniffer guess every reading decision.
guess = duck.sql("SELECT * FROM 'm505_excerpt.csv'")
# The malformed line defeats the guess: DuckDB 2.0 rejects the comma and sees one single column.
print("B1. Columns found by guessing:", len(guess.columns))
# Second attempt: state the delimiter, the quote character and the header, and keep the lines that do not fit.
told = duck.sql("SELECT * FROM read_csv('m505_excerpt.csv', delim = ',', quote = '\"', header = true, store_rejects = true)")
# With the format stated, the 13 columns of the header are found.
print("B2. Columns found when DuckDB is told the format:", len(told.columns))
# Store the result as a table inside mercadillo.duckdb, where DuckDB keeps every column separately (a column store).
duck.execute("CREATE TABLE orders_flat AS SELECT * FROM read_csv('m505_excerpt.csv', delim = ',', quote = '\"', header = true, store_rejects = true)")
# Count the rows that were loaded into the table.
print("B3. Rows in orders_flat:", duck.execute("SELECT count(*) FROM orders_flat").fetchone()[0])
# The temporary table reject_errors lists every line that did not fit, with its line number and the reason.
print("B4. Lines set aside:", duck.execute("SELECT line, error_type FROM reject_errors").fetchall())
# DuckDB checks types strictly: try to put the text 'two' into the BIGINT column quantity.
try:
    # This INSERT is expected to fail.
    duck.execute("INSERT INTO orders_flat (quantity) VALUES ('two')")
# A ConversionException is DuckDB's error for a value that does not match the column type.
except duckdb.ConversionException as error:
    # Print the first line of DuckDB's error message.
    print("B5. DuckDB refuses 'two':", str(error).splitlines()[0])
# An analytical question that needs only one of the thirteen columns: how many lines come from Madrid, in any spelling?
print("B6. Madrid lines, any spelling:", duck.execute("SELECT count(*) FROM orders_flat WHERE lower(city) = 'madrid'").fetchone()[0])
# Close the connection; the table stays inside the file mercadillo.duckdb.
duck.close()
# PART C - each database is one ordinary file: list both files with their sizes.
for name in ("stall.sqlite", "mercadillo.duckdb"):
    # os.path.getsize returns the size of a file in bytes.
    print("C.  ", name, os.path.getsize(name), "bytes")
