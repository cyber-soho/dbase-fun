-- IT 505 · Lab 1 · Step 1 — starter queries for DuckDB (Class 2).
-- Run the statements one by one. Replace the file name by the full path of the file on your computer,
-- for example 'C:/IT505/lab1/mercadillo505_orders_flat.csv'. Every statement has its explanation in the comment above it.

-- 1. The simplest reading: DuckDB guesses the delimiter, the header and the types. Count the columns of the result.
SELECT * FROM 'mercadillo505_orders_flat.csv' LIMIT 5;

-- 2. The same reading, described: one row per column that DuckDB found, with the type that it guessed.
DESCRIBE SELECT * FROM 'mercadillo505_orders_flat.csv';

-- 3. A careful reading: malformed lines are set apart in a table of rejects instead of spoiling the whole file.
SELECT COUNT(*) AS readable_rows FROM read_csv('mercadillo505_orders_flat.csv', store_rejects = true);

-- 4. The rejects: the number of the line in the file, the kind of error and its explanation.
SELECT line, error_type, error_message FROM reject_errors;

-- 5. Load the readable rows into a table. all_varchar keeps every value as text, exactly as it is typed in the file.
CREATE OR REPLACE TABLE orders_flat AS
  SELECT * FROM read_csv('mercadillo505_orders_flat.csv', ignore_errors = true, all_varchar = true);

-- 6. The profile of the file: for every column the guessed type, the estimated number of distinct values and the share of empty cells.
SUMMARIZE SELECT * FROM read_csv('mercadillo505_orders_flat.csv', ignore_errors = true);

-- 7. Problem hunting, first query: every spelling of the city with its number of rows.
SELECT city, COUNT(*) AS lines FROM orders_flat GROUP BY city ORDER BY city;

-- 8. Problem hunting, second query: lines that appear more than once. GROUP BY ALL groups by every column that is not counted.
SELECT order_id, product, COUNT(*) AS copies FROM orders_flat GROUP BY ALL HAVING COUNT(*) > 1;

-- 9. YOUR TURN: write one query for each other kind of problem (dates, empty cells, names and e-mail addresses).

-- 10. YOUR TURN: answer those of your five business questions that one table can answer. An example of the form:
--     revenue per product, largest first (price and quantity are text in orders_flat, so they are converted first).
SELECT product, SUM(CAST(unit_price AS DECIMAL(8,2)) * CAST(quantity AS INTEGER)) AS revenue
FROM orders_flat GROUP BY product ORDER BY revenue DESC LIMIT 5;
