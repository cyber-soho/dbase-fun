-- IT 505 · Class 4 · Lesson 2 · Example 2 — The same ten million order lines as CSV and as Parquet (DuckDB 2.0).
-- Task: the finance team wants answers from a much larger order history; we compare the size of the two files and the time of the same question.
-- Link to the lecture: columnar storage, compression and statistics (Parquet) against row-by-row text (CSV).
-- Run it in DBeaver (DuckDB connection) or in the DuckDB command line; keep the starter file in the folder where DuckDB runs.
-- In the DuckDB command line, type .timer on first: DuckDB then prints the time of every statement.
-- Not enough disk space (the CSV file needs about 1.7 GB)? Replace 5120 by 512 in Step 2: one million lines show the same effect.

-- Step 1. Read the starter file of Lab 1; ignore_errors = true sets the one malformed line aside, so the 1,954 readable lines remain.
CREATE OR REPLACE TABLE orders AS SELECT * FROM read_csv('mercadillo505_orders_flat.csv', ignore_errors = true);
-- Count the lines of the small table, to know what we start from.
SELECT COUNT(*) AS lines_in_starter_file FROM orders;

-- Step 2. Make the data big: range(5120) gives the numbers 0 to 5119, and CROSS JOIN pairs every order line with every number.
CREATE OR REPLACE TABLE orders_big AS
-- line_id glues the order number and the copy number ("M505-1001-0", "M505-1001-1" ...), so that every line has its own identifier.
SELECT o.order_id || '-' || r.range AS line_id, o.*
-- Each of the 1,954 lines appears 5,120 times: 1,954 × 5,120 = 10,004,480 lines.
FROM orders AS o CROSS JOIN range(5120) AS r;
-- Check the number of lines of the big table.
SELECT COUNT(*) AS lines_now FROM orders_big;

-- Step 3. Save the big table as CSV: plain text, one line per order line, the values separated by commas.
COPY orders_big TO 'orders_big.csv' (HEADER true, DELIMITER ',');
-- Step 4. Save the same table as Parquet: stored column by column, compressed, with statistics for every block of rows.
COPY orders_big TO 'orders_big.parquet' (FORMAT parquet);

-- Step 5. Compare the sizes: read_blob lists the files that match the pattern, and size is given in bytes (1 MB = 1,000,000 bytes).
SELECT filename, round(size / 1e6, 1) AS megabytes FROM read_blob('orders_big.*') ORDER BY size DESC;

-- Step 6. The same question on both files: how many order lines come from customers in Madrid? Note the time of each answer.
SELECT COUNT(*) AS madrid_lines FROM 'orders_big.csv' WHERE city = 'Madrid';
-- On the Parquet file DuckDB reads only the city column, which is stored together and compressed.
SELECT COUNT(*) AS madrid_lines FROM 'orders_big.parquet' WHERE city = 'Madrid';

-- Step 7. Statistics: Parquet stores the smallest and the largest value of every column for every row group (block of rows).
SELECT row_group_id, path_in_schema AS column_name, stats_min_value AS smallest, stats_max_value AS largest, num_values
-- parquet_metadata reads only the footer of the file, so this answer is immediate.
FROM parquet_metadata('orders_big.parquet') WHERE path_in_schema = 'unit_price' AND row_group_id < 3;
-- No row group has a price above 11.50, so DuckDB can skip every block without reading it: the answer is 0, at once.
SELECT COUNT(*) AS lines_above_20_euros FROM 'orders_big.parquet' WHERE unit_price > 20;

-- SQL Server note: SQL Server reads a CSV file with BULK INSERT or OPENROWSET; Parquet files are read through PolyBase or OPENROWSET in recent versions.
