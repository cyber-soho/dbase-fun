-- IT 505 · Class 2 · Lesson 3 · Five business questions for Monday's meeting (DuckDB 2.0; fictional Mercadillo 505 data).
-- Create the table orders_flat, replacing it if it already exists, from the result of the query that follows.
CREATE OR REPLACE TABLE orders_flat AS
-- Read the CSV file where it lies, stating the delimiter, the quote character and the header, and keep the malformed line in reject_errors.
SELECT * FROM read_csv('m505_excerpt.csv', delim = ',', quote = '"', header = true, store_rejects = true);

-- Q1a. What was sold on Saturday 21 November? First attempt: show the order, the date and the product ...
SELECT order_id, order_date, product
-- ... of the table orders_flat ...
FROM orders_flat
-- ... for the rows whose date text is exactly '2026-11-21' (order_date is text, because the file mixes two date formats).
WHERE order_date = '2026-11-21';

-- Q1b. Corrected attempt: the same three columns ...
SELECT order_id, order_date, product
-- ... of the same table ...
FROM orders_flat
-- ... for the rows whose date text is either spelling of 21 November 2026; IN lists the accepted values.
WHERE order_date IN ('2026-11-21', '21/11/2026');

-- Q2. Which lines come from Madrid, in any spelling? Show the order, the city as written, and the product ...
SELECT order_id, city, product
-- ... of the table orders_flat ...
FROM orders_flat
-- ... for the rows whose city, converted to lower case, is 'madrid' (catches Madrid, MADRID and madrid) ...
WHERE lower(city) = 'madrid'
-- ... sorted by order number, so that the result is easy to read.
ORDER BY order_id;

-- Q3. Which three lines brought the most money? Show the order, the product, and price × quantity rounded to cents, named line_total ...
SELECT order_id, product, round(unit_price * quantity, 2) AS line_total
-- ... of the table orders_flat ...
FROM orders_flat
-- ... sorted by the alias line_total from the largest to the smallest (ORDER BY runs after SELECT, so the alias exists) ...
ORDER BY line_total DESC
-- ... and keep only the first three rows of the sorted result.
LIMIT 3;

-- Q4. Which payment methods do customers use? Show each different payment method once ...
SELECT DISTINCT payment_method
-- ... of the table orders_flat ...
FROM orders_flat
-- ... in alphabetical order (the empty payment method of M505-1046 appears as one NULL row).
ORDER BY payment_method;

-- Q5a. Which lines have no quantity? Wrong test first: show the order, the product and the quantity ...
SELECT order_id, product, quantity
-- ... of the table orders_flat ...
FROM orders_flat
-- ... where quantity equals NULL: this comparison is unknown for every row, so no row is returned.
WHERE quantity = NULL;

-- Q5b. Correct test: the same three columns ...
SELECT order_id, product, quantity
-- ... of the same table ...
FROM orders_flat
-- ... where the quantity is missing; IS NULL is the only correct test for a missing value.
WHERE quantity IS NULL;

-- SQL Server note (comment only, not run here): SQL Server writes Q3 as SELECT TOP 3 order_id, product, ROUND(unit_price * quantity, 2) AS line_total FROM orders_flat ORDER BY line_total DESC;
