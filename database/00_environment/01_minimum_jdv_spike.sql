-- MySQL JSON Duality Views minimum capability spike
-- Runtime: MySQL Community Server 9.7.2
-- Database: jdv_spike

USE jdv_spike;

DROP VIEW IF EXISTS customer_orders_dv;
DROP VIEW IF EXISTS order_dv;

DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS customers;

CREATE TABLE customers (
    customer_id INT NOT NULL,
    name VARCHAR(100) NOT NULL,
    PRIMARY KEY (customer_id)
);

CREATE TABLE orders (
    order_id INT NOT NULL,
    customer_id INT NOT NULL,
    product VARCHAR(100) NOT NULL,
    amount DECIMAL(10,2) NOT NULL,
    PRIMARY KEY (order_id),
    CONSTRAINT fk_orders_customer
        FOREIGN KEY (customer_id)
        REFERENCES customers (customer_id)
);

INSERT INTO customers (
    customer_id,
    name
)
VALUES
    (1, 'Alice'),
    (2, 'Bob');

INSERT INTO orders (
    order_id,
    customer_id,
    product,
    amount
)
VALUES
    (1, 1, 'Milk', 10.00),
    (2, 1, 'Curd', 5.00),
    (3, 2, 'Flour', 20.00),
    (4, 2, 'Biscuits', 5.00);

CREATE JSON RELATIONAL DUALITY VIEW customer_orders_dv AS
SELECT JSON_DUALITY_OBJECT(
    '_id': customer_id,
    'customer_name': name,
    'orders': (
        SELECT JSON_ARRAYAGG(
            JSON_DUALITY_OBJECT(
                'order_id': order_id,
                'product': product,
                'amount': amount
            )
        )
        FROM orders
        WHERE orders.customer_id = customers.customer_id
    )
)
FROM customers;

CREATE JSON RELATIONAL DUALITY VIEW order_dv AS
SELECT JSON_DUALITY_OBJECT(
    WITH (INSERT, UPDATE, DELETE)
    '_id': order_id,
    'product': product,
    'amount': amount,
    'customer': (
        SELECT JSON_DUALITY_OBJECT(
            WITH (INSERT, UPDATE)
            'customer_id': customer_id,
            'customer_name': name
        )
        FROM customers
        WHERE customers.customer_id = orders.customer_id
    )
)
FROM orders;

SELECT
    'customers' AS object_name,
    COUNT(*) AS row_count
FROM customers

UNION ALL

SELECT
    'orders' AS object_name,
    COUNT(*) AS row_count
FROM orders;

SELECT
    TABLE_NAME,
    JSON_COLUMN_NAME,
    ROOT_TABLE_NAME,
    ALLOW_INSERT,
    ALLOW_UPDATE,
    ALLOW_DELETE,
    READ_ONLY,
    STATUS
FROM INFORMATION_SCHEMA.JSON_DUALITY_VIEWS
WHERE TABLE_SCHEMA = 'jdv_spike'
ORDER BY TABLE_NAME;
