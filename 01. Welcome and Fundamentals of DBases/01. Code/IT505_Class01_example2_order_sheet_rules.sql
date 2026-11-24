-- Create the table. Each of the next lines declares one column and the rules (constraints) that the DBMS will check for it.
CREATE TABLE order_lines (
  -- The order number is text and may not be empty.
  order_id   TEXT NOT NULL,
  -- The name of the customer may not be empty.
  customer   TEXT NOT NULL,
  -- The city may not be empty and must be one of the three agreed spellings.
  city       TEXT NOT NULL CHECK (city IN ('Madrid', 'Getafe', 'Alcobendas')),
  -- The name of the product may not be empty.
  product    TEXT NOT NULL,
  -- The unit price may not be empty and must be greater than zero; NUMERIC(8,2) stores money exactly, with two decimals.
  unit_price NUMERIC(8,2) NOT NULL CHECK (unit_price > 0),
  -- The quantity is a whole number, may not be empty and must be greater than zero.
  quantity   INTEGER NOT NULL CHECK (quantity > 0),
  -- One product can appear only once in one order: this pair of columns is the primary key of the table.
  PRIMARY KEY (order_id, product)
-- End of the table definition; from here on, every new row is checked against the rules above.
);
-- Row 1 of the sheet: every rule is met, so the row is accepted.
INSERT INTO order_lines VALUES ('M505-1041', 'Marta Iglesias', 'Madrid', 'Olive oil 1 L', 9.80, 2);
-- Row 2: the same order as row 1 with another product; the pair (order, product) is new, so the row is accepted.
INSERT INTO order_lines VALUES ('M505-1041', 'Marta Iglesias', 'Madrid', 'Sourdough loaf', 4.20, 1);
-- Row 3: a new order from Getafe; accepted.
INSERT INTO order_lines VALUES ('M505-1042', 'Diego Navarro', 'Getafe', 'Manchego cheese 250 g', 7.50, 1);
-- Row 4: the city is typed 'MADRID', which is not in the list of the CHECK rule, so the DBMS refuses the row.
INSERT INTO order_lines VALUES ('M505-1043', 'Sofía Ortiz', 'MADRID', 'Honey 500 g', 6.90, 1);
-- Row 5: an order from Alcobendas; accepted.
INSERT INTO order_lines VALUES ('M505-1044', 'Pablo Serrano', 'Alcobendas', 'Oranges 2 kg', 3.60, 3);
-- Row 6: the same order and the same product as row 3; the primary key refuses the duplicate.
INSERT INTO order_lines VALUES ('M505-1042', 'Diego Navarro', 'Getafe', 'Manchego cheese 250 g', 7.50, 1);
-- Row 7: the quantity is empty (NULL); the NOT NULL rule refuses the row.
INSERT INTO order_lines VALUES ('M505-1045', 'Elena Vidal', 'Madrid', 'Almonds 200 g', 5.40, NULL);
-- Row 8: a new order from Getafe; accepted.
INSERT INTO order_lines VALUES ('M505-1046', 'Javier Molina', 'Getafe', 'Olive oil 1 L', 9.80, 1);
-- Row 9: a new order from Madrid; accepted.
INSERT INTO order_lines VALUES ('M505-1047', 'Nuria Campos', 'Madrid', 'Sourdough loaf', 4.20, 2);
-- Row 10: the same order as row 9 with another product; accepted.
INSERT INTO order_lines VALUES ('M505-1047', 'Nuria Campos', 'Madrid', 'Honey 500 g', 6.90, 1);
-- Row 4 again, with the agreed spelling of the city: accepted.
INSERT INTO order_lines VALUES ('M505-1043', 'Sofía Ortiz', 'Madrid', 'Honey 500 g', 6.90, 1);
-- Row 7 again, after the customer confirmed a quantity of 2: accepted.
INSERT INTO order_lines VALUES ('M505-1045', 'Elena Vidal', 'Madrid', 'Almonds 200 g', 5.40, 2);
-- The manager's question, answered from the checked rows: orders and revenue per city, the largest revenue first.
SELECT city, COUNT(DISTINCT order_id) AS orders, SUM(unit_price * quantity) AS revenue FROM order_lines GROUP BY city ORDER BY revenue DESC;
