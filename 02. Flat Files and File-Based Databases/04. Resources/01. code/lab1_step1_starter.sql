-- IT 505 · Class 2 · Studio · Lab 1, Step 1 — starter script (DuckDB 2.0 in DBeaver). Replace the path with the full path of YOUR file.
-- Step A. The simplest reading: let DuckDB guess everything, and note how many columns it finds.
SELECT * FROM 'C:/IT505/mercadillo505_orders_flat.csv' LIMIT 5;
-- Step B. DESCRIBE shows the columns DuckDB found and the type it guessed for each one.
DESCRIBE SELECT * FROM 'C:/IT505/mercadillo505_orders_flat.csv';
-- Step C. State the format yourself and keep every line that does not fit; CREATE TABLE … AS reads the whole file.
CREATE OR REPLACE TABLE orders_flat AS
-- read_csv with the delimiter, the quote character and the header stated; store_rejects keeps the evidence.
SELECT * FROM read_csv('C:/IT505/mercadillo505_orders_flat.csv', delim = ',', quote = '"', header = true, store_rejects = true);
-- Step D. Which lines were set aside, at which line number, and why?
SELECT line, column_idx, error_type, error_message FROM reject_errors;
-- Step E. Profile the table: type, approximate distinct values and percentage of NULLs for every column.
SUMMARIZE orders_flat;
-- Step F. Every spelling of every city (repeat for payment_method, status, category, customer_name …).
SELECT DISTINCT city FROM orders_flat ORDER BY city;
-- Step G. Your five business questions from Step 0 (Class 1): for each one write the question as a comment, then the query.
-- Q1 <business wording>
SELECT order_id, order_date, product FROM orders_flat WHERE order_date IN ('2026-11-21', '21/11/2026');
-- Result: <number of rows> · Reading: <one sentence that a manager understands>
-- Q2 …  Q3 …  Q4 …  Q5 …
-- Spanish-locale file with decimal commas? Add decimal_separator = ',' to read_csv.
-- SQL Server note: SQL Server writes SELECT TOP 5 … where PostgreSQL, SQLite and DuckDB write … LIMIT 5.
