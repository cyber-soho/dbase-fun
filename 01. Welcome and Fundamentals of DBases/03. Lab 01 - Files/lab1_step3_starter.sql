-- IT 505 · Lab 1 · Step 3 — starter script for PostgreSQL (Class 4).
-- It gives the staging table and the two loading patterns. The tables of your own design are yours to write.

-- 1. The staging table takes the file exactly as it is: 13 columns, all text, no rule at all.
CREATE TABLE staging_orders (
  order_id TEXT, order_date TEXT, customer_name TEXT, customer_email TEXT, city TEXT, referred_by TEXT,
  product TEXT, category TEXT, producer TEXT, unit_price TEXT, quantity TEXT, payment_method TEXT, status TEXT
);

-- 2. Import the repaired copy of the file into staging_orders:
--    in DBeaver, right-click the table and choose Import Data; in psql, use the line below with your own path.
-- \copy staging_orders FROM 'C:/IT505/lab1/mercadillo505_orders_flat_repaired.csv' WITH (FORMAT csv, HEADER true)

-- 3. Check the import: the staging table must hold 1,955 rows.
SELECT COUNT(*) AS staging_rows FROM staging_orders;

-- 4. Pattern for a parent table: one row per distinct value (write your own CREATE TABLE categories first, in schema.sql).
-- INSERT INTO categories (name)
-- SELECT DISTINCT category FROM staging_orders ORDER BY category;

-- 5. Pattern for a child table: the key of the parent is looked up with a join on the value that both tables share.
-- INSERT INTO products (name, category_id, unit_price)
-- SELECT DISTINCT s.product, c.category_id, s.unit_price::numeric(8,2)
-- FROM staging_orders s JOIN categories c ON c.name = s.category;

-- 6. A date typed as day/month/year must be read with to_date; a direct conversion reads '05/11/2026' as 11 May.
SELECT order_date,
       CASE WHEN order_date LIKE '%/%' THEN to_date(order_date, 'DD/MM/YYYY') ELSE order_date::date END AS order_date_clean
FROM staging_orders WHERE order_date LIKE '%/%' LIMIT 5;

-- 7. Spaces around a value and empty texts: TRIM removes the spaces, NULLIF turns the empty text into NULL.
SELECT DISTINCT city, NULLIF(TRIM(city), '') AS city_clean FROM staging_orders ORDER BY city;

-- 8. YOUR TURN: write load.sql for all your tables, parents first, then compare your row counts with the reference values.

-- 9. YOUR TURN: write three INSERT statements that your database must refuse, and keep the three error messages.
