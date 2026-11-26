-- IT 505 · Lab 2 of 3 · Scale and Seal · Part A (Scale) and step B5 — DuckDB script
-- Educational material, Cyber.SoHo. Use only the fictional Mercadillo 505 file or open data you may use (Legal Notice §6.7).
-- How to run: put this file in the folder of your starter file, then in a terminal:  duckdb lab2.duckdb < lab2_scale.sql
-- In DBeaver: open a DuckDB connection, open this file, and run one statement at a time (Ctrl+Enter); skip the two lines that start with a dot.
-- Tested with DuckDB 2.0.1 and 1.4.4 (November 2026). Every tool is a proposal: any other suitable engine may replace DuckDB.

-- Ask the DuckDB command line to print the time of every statement (DBeaver shows the time in its result panel instead).
.timer on
-- Show results as boxed tables in the terminal.
.mode duckbox

-- ===== A0. Load the starter file =====================================================
-- Read the CSV file into a table; ignore_errors skips the lines that cannot be read (your file has at least one).
CREATE OR REPLACE TABLE orders AS SELECT * FROM read_csv('mercadillo505_orders_flat.csv', ignore_errors = true);

-- ===== A1. The five Vs of YOUR data ===================================================
-- Volume: the number of order lines that DuckDB could read, and the number of different days and orders.
SELECT COUNT(*) AS order_lines, COUNT(DISTINCT order_id) AS orders, COUNT(DISTINCT order_date) AS days FROM orders;
-- Velocity: the average number of order lines per day in the file (one day = one value of order_date).
SELECT ROUND(COUNT(*) / COUNT(DISTINCT order_date), 1) AS lines_per_day FROM orders;
-- Variety: the column names and the type DuckDB guessed for each column.
DESCRIBE orders;
-- Veracity: every spelling of the city with its number of lines (several spellings of one city = a veracity problem).
SELECT city, COUNT(*) AS order_lines FROM orders GROUP BY city ORDER BY order_lines DESC;
-- Veracity: how many lines have no quantity or no city.
SELECT COUNT(*) FILTER (WHERE quantity IS NULL) AS no_quantity, COUNT(*) FILTER (WHERE city IS NULL OR trim(city) = '') AS no_city FROM orders;

-- ===== A2. The question of the MapReduce program, asked in SQL ========================
-- Order lines per city after cleaning the spelling: lower case, no spaces around, no accents; compare with lab2_mapreduce.py.
SELECT strip_accents(lower(trim(city))) AS city_key, COUNT(*) AS order_lines FROM orders WHERE trim(coalesce(city, '')) <> '' GROUP BY city_key ORDER BY order_lines DESC;

-- ===== A3. Make it big, then store it twice ===========================================
-- Repeat every line 5,120 times (about 10 million lines, 1.7 GB as CSV); with little free disk or memory, write 512 instead of 5120.
CREATE OR REPLACE TABLE orders_big AS SELECT o.order_id || '-' || r.range AS line_id, o.* FROM orders AS o CROSS JOIN range(5120) AS r;
-- Check the new number of lines.
SELECT COUNT(*) AS lines_now FROM orders_big;
-- Save the big table as one CSV file (text, row by row).
COPY orders_big TO 'orders_big.csv' (HEADER true, DELIMITER ',');
-- Save the same table as one Parquet file (binary, column by column, compressed).
COPY orders_big TO 'orders_big.parquet' (FORMAT parquet);
-- Compare the two file sizes in megabytes.
SELECT filename, ROUND(size / 1e6, 1) AS megabytes FROM read_blob('orders_big.*') ORDER BY filename;
-- The same question on the CSV file: run it three times and keep the middle time (the median) in your worksheet.
SELECT COUNT(*) AS madrid_lines FROM 'orders_big.csv' WHERE city = 'Madrid';
-- Second run on the CSV file.
SELECT COUNT(*) AS madrid_lines FROM 'orders_big.csv' WHERE city = 'Madrid';
-- Third run on the CSV file.
SELECT COUNT(*) AS madrid_lines FROM 'orders_big.csv' WHERE city = 'Madrid';
-- The same question on the Parquet file, first run.
SELECT COUNT(*) AS madrid_lines FROM 'orders_big.parquet' WHERE city = 'Madrid';
-- Second run on the Parquet file.
SELECT COUNT(*) AS madrid_lines FROM 'orders_big.parquet' WHERE city = 'Madrid';
-- Third run on the Parquet file.
SELECT COUNT(*) AS madrid_lines FROM 'orders_big.parquet' WHERE city = 'Madrid';

-- ===== A4. The statistics inside the Parquet file =====================================
-- How many row groups the file has, and how many rows are in each.
SELECT COUNT(*) AS row_groups, MIN(row_group_num_rows) AS smallest_group, MAX(row_group_num_rows) AS largest_group FROM (SELECT DISTINCT row_group_id, row_group_num_rows FROM parquet_metadata('orders_big.parquet'));
-- The smallest and largest unit price stored for the first three row groups (read from the footer, no row is read).
SELECT row_group_id, stats_min_value AS smallest_price, stats_max_value AS largest_price FROM parquet_metadata('orders_big.parquet') WHERE path_in_schema = 'unit_price' ORDER BY row_group_id LIMIT 3;
-- Ask for prices above the largest value you just read (change 20 if your largest price is higher): the row groups are skipped.
SELECT COUNT(*) AS lines_above_20_euros FROM 'orders_big.parquet' WHERE unit_price > 20;

-- ===== B5. Two spellings, two hashes ==================================================
-- SHA-256 of two spellings of the same city: compare the two results (write two spellings of YOUR city if it is not Madrid).
SELECT sha256('Madrid') AS hash_a, sha256('madrid') AS hash_b;
