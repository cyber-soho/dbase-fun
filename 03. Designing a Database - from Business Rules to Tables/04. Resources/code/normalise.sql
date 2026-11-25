-- IT 505 · Class 3 · Example 4 — one wide table becomes four tables. Educational material — Cyber.SoHo / Asen Grozdanov. Fictional data (Mercadillo 505).
-- Runs unchanged on DuckDB 2.0, SQLite 3 and PostgreSQL 16 or later.

-- Create the wide table: one row per order line, exactly as in the export file.
CREATE TABLE orders_flat (
-- The order number: first part of the key.
  order_id       TEXT,
-- A fact about the order.
  order_date     DATE,
-- A fact about the customer.
  customer_name  TEXT,
-- The value that identifies the customer.
  customer_email TEXT,
-- Another fact about the customer.
  city           TEXT,
-- The product name: second part of the key.
  product        TEXT,
-- A fact about the product.
  category       TEXT,
-- Another fact about the product.
  unit_price     DECIMAL(8,2),
-- The only fact about the pair (order, product).
  quantity       INTEGER
-- End of the definition.
);

-- Six order lines from the weekend of 21 and 22 November 2026.
INSERT INTO orders_flat VALUES
-- Line 1: order M505-1041 of Lucía, first product.
  ('M505-1041', '2026-11-21', 'Lucía Fernández', 'lucia.fernandez@example.es', 'Madrid', 'Manchego cheese 250 g', 'Cheese', 7.40, 2),
-- Line 2: the same order, second product; five values of line 1 are repeated.
  ('M505-1041', '2026-11-21', 'Lucía Fernández', 'lucia.fernandez@example.es', 'Madrid', 'Olive oil 1 L', 'Oil', 9.80, 1),
-- Line 3: an order of Javier.
  ('M505-1042', '2026-11-21', 'Javier Ortega', 'javier.ortega@example.es', 'Madrid', 'Turrón 300 g', 'Sweets', 6.90, 3),
-- Line 4: the only order of Marta.
  ('M505-1043', '2026-11-21', 'Marta Ruiz', 'marta.ruiz@example.es', 'Alcalá de Henares', 'Saffron 1 g', 'Spices', 5.50, 4),
-- Line 5: a second order of Lucía; her name, address and city are written a third time.
  ('M505-1049', '2026-11-22', 'Lucía Fernández', 'lucia.fernandez@example.es', 'Madrid', 'Turrón 300 g', 'Sweets', 6.90, 1),
-- Line 6: a second order of Javier.
  ('M505-1050', '2026-11-22', 'Javier Ortega', 'javier.ortega@example.es', 'Madrid', 'Saffron 1 g', 'Spices', 5.50, 2);

-- Count the rows, and count how many different customers, orders and products they describe.
SELECT COUNT(*) AS line_rows,
-- COUNT(DISTINCT …) counts every value once.
       COUNT(DISTINCT customer_email) AS customers,
-- The same for the orders.
       COUNT(DISTINCT order_id) AS orders,
-- The same for the products.
       COUNT(DISTINCT product) AS products
-- All four numbers come from the wide table.
FROM orders_flat;

-- Lucía moves to Getafe, and somebody corrects only the row of her latest order.
UPDATE orders_flat SET city = 'Getafe'
-- Only one of her three rows is changed.
WHERE order_id = 'M505-1049';

-- Ask the table where Lucía lives; DISTINCT shows every different answer once.
SELECT DISTINCT customer_name, city
-- The wide table is the only source.
FROM orders_flat
-- Keep the rows of Lucía.
WHERE customer_email = 'lucia.fernandez@example.es'
-- Sort the answers.
ORDER BY city;

-- Put the old city back before the split.
UPDATE orders_flat SET city = 'Madrid'
-- The same single row.
WHERE order_id = 'M505-1049';

-- Create products from the result of a query: the columns that depend on the product name only.
CREATE TABLE products AS
-- DISTINCT keeps every product once.
SELECT DISTINCT product, category, unit_price
-- The values come from the wide table.
FROM orders_flat;

-- Create orders_2nf: the columns that depend on the order number only.
CREATE TABLE orders_2nf AS
-- DISTINCT keeps every order once.
SELECT DISTINCT order_id, order_date, customer_name, customer_email, city
-- The values come from the wide table.
FROM orders_flat;

-- Create order_lines: the key (order_id, product) and the one column that depends on both parts.
CREATE TABLE order_lines AS
-- No DISTINCT is needed: every pair appears once.
SELECT order_id, product, quantity
-- The values come from the wide table.
FROM orders_flat;

-- Look at the orders after the first split.
SELECT order_id, customer_name, city
-- The table of the second normal form.
FROM orders_2nf
-- Sort by customer to see the repetition.
ORDER BY customer_name, order_id;

-- Create customers: name and city depend on the e-mail address, not on the order number.
CREATE TABLE customers AS
-- DISTINCT keeps every customer once.
SELECT DISTINCT customer_email, customer_name, city
-- The values come from orders_2nf.
FROM orders_2nf;

-- Create orders: the order number, its date, and the e-mail address as the link to the customer.
CREATE TABLE orders AS
-- Name and city are left out: they live in customers now.
SELECT order_id, order_date, customer_email
-- The values come from orders_2nf.
FROM orders_2nf;

-- Lucía moves to Getafe again; this time her city is stored in exactly one row.
UPDATE customers SET city = 'Getafe'
-- One customer, one row.
WHERE customer_email = 'lucia.fernandez@example.es';

-- Ask again where Lucía lives.
SELECT customer_name, city
-- The table customers is the only place where a city is stored.
FROM customers
-- Keep the row of Lucía.
WHERE customer_email = 'lucia.fernandez@example.es';

-- Rebuild the wide rows from the four tables and count them.
SELECT COUNT(*) AS rebuilt_rows
-- Start from the order lines.
FROM order_lines
-- USING (order_id) connects rows that have the same order number.
JOIN orders    USING (order_id)
-- The e-mail address connects each order to its customer.
JOIN customers USING (customer_email)
-- The product name connects each line to its product.
JOIN products  USING (product);

-- Count the rows of each new table in one result line.
SELECT (SELECT COUNT(*) FROM customers)   AS customers,
-- One row per order.
       (SELECT COUNT(*) FROM orders)      AS orders,
-- One row per product.
       (SELECT COUNT(*) FROM products)    AS products,
-- One row per order line.
       (SELECT COUNT(*) FROM order_lines) AS order_lines;
