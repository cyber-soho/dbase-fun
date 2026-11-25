-- IT 505 · Class 3 · Example 3 — primary keys and foreign keys at work. Educational material — Cyber.SoHo / Asen Grozdanov. Fictional data (Mercadillo 505).
-- Engine: SQLite 3 (the PRAGMA line is needed). Four statements are refused on purpose: they are the four tests.

-- SQLite checks foreign keys only after this statement; DuckDB and PostgreSQL always check them, so delete this line there.
PRAGMA foreign_keys = ON;

-- Create the table customers: one row per customer.
CREATE TABLE customers (
-- The primary key: a whole number that identifies one customer. PRIMARY KEY means unique and never empty.
  customer_id INTEGER PRIMARY KEY,
-- The name is required: NOT NULL refuses an empty value.
  name        TEXT NOT NULL,
-- The e-mail address is required, and UNIQUE refuses the same address for two customers.
  email       TEXT NOT NULL UNIQUE,
-- The city may be empty when it is not known yet.
  city        TEXT
-- End of the definition of customers.
);

-- Create the table products: one row per product.
CREATE TABLE products (
-- The primary key of a product.
  product_id  INTEGER PRIMARY KEY,
-- The name is required and may not be used twice.
  name        TEXT NOT NULL UNIQUE,
-- The price of one unit: an exact number with two decimal places.
  unit_price  DECIMAL(8,2) NOT NULL
-- End of the definition of products.
);

-- Create the table orders: one row per order.
CREATE TABLE orders (
-- The primary key is the order number that the business already prints, for example M505-1041.
  order_id    TEXT PRIMARY KEY,
-- The date of the order is required.
  order_date  DATE NOT NULL,
-- The foreign key: it must contain a customer_id that exists in customers. REFERENCES states the link.
  customer_id INTEGER NOT NULL REFERENCES customers (customer_id)
-- End of the definition of orders.
);

-- Create the table order_lines: one row per product inside an order.
CREATE TABLE order_lines (
-- First foreign key: the order to which the line belongs.
  order_id    TEXT NOT NULL REFERENCES orders (order_id),
-- Second foreign key: the product that the line sells.
  product_id  INTEGER NOT NULL REFERENCES products (product_id),
-- The quantity of this product in this order.
  quantity    INTEGER NOT NULL,
-- A composite primary key: the pair (order_id, product_id) identifies one line.
  PRIMARY KEY (order_id, product_id)
-- End of the definition of order_lines.
);

-- Add three customers; the columns are filled in the order of the definition.
INSERT INTO customers VALUES
-- Customer 1.
  (1, 'Lucía Fernández', 'lucia.fernandez@example.es', 'Madrid'),
-- Customer 2.
  (2, 'Javier Ortega',   'javier.ortega@example.es',   'Madrid'),
-- Customer 3.
  (3, 'Marta Ruiz',      'marta.ruiz@example.es',      'Alcalá de Henares');

-- Add three products.
INSERT INTO products VALUES
-- Product 1.
  (1, 'Manchego cheese 250 g', 7.40),
-- Product 2.
  (2, 'Olive oil 1 L',         9.80),
-- Product 3.
  (3, 'Turrón 300 g',          6.90);

-- Add three orders; the last value of each row is the customer who placed the order.
INSERT INTO orders VALUES
-- An order of customer 1.
  ('M505-1041', '2026-11-21', 1),
-- An order of customer 2.
  ('M505-1042', '2026-11-21', 2),
-- An order of customer 3.
  ('M505-1043', '2026-11-21', 3);

-- Add three order lines: order, product, quantity.
INSERT INTO order_lines VALUES
-- Order M505-1041 contains 2 units of product 1.
  ('M505-1041', 1, 2),
-- Order M505-1041 also contains 1 unit of product 2.
  ('M505-1041', 2, 1),
-- Order M505-1042 contains 3 units of product 3.
  ('M505-1042', 3, 3);

-- Test 1, entity integrity: customer number 1 exists already, so the primary key must refuse this row.
INSERT INTO customers VALUES (1, 'Pablo Martín', 'pablo.martin@example.es', 'Madrid');

-- Test 2, referential integrity: there is no customer number 99, so the foreign key must refuse this order.
INSERT INTO orders VALUES ('M505-1099', '2026-11-22', 99);

-- Test 3, referential integrity again: customer 1 has an order, so deleting the customer would leave an order that points to nobody.
DELETE FROM customers WHERE customer_id = 1;

-- Test 4, composite key: the pair (M505-1041, 1) exists already, so a second line with the same pair is refused.
INSERT INTO order_lines VALUES ('M505-1041', 1, 5);

-- Choose four columns from four tables; c, o, l and p are short names for the tables.
SELECT c.name, o.order_id, p.name AS product, l.quantity
-- Start from the customers.
FROM customers c
-- Go to the orders of each customer: foreign key = primary key.
JOIN orders o      ON o.customer_id = c.customer_id
-- Go to the lines of each order.
JOIN order_lines l ON l.order_id    = o.order_id
-- Go to the product of each line.
JOIN products p    ON p.product_id  = l.product_id
-- Sort the result so that it reads the same on every engine.
ORDER BY o.order_id, p.name;
