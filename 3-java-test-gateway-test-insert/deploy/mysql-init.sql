CREATE DATABASE IF NOT EXISTS order_fulfillment
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS 'mockotel'@'localhost' IDENTIFIED BY 'mockotel_pwd';
CREATE USER IF NOT EXISTS 'mockotel'@'127.0.0.1' IDENTIFIED BY 'mockotel_pwd';

GRANT ALL PRIVILEGES ON order_fulfillment.* TO 'mockotel'@'localhost';
GRANT ALL PRIVILEGES ON order_fulfillment.* TO 'mockotel'@'127.0.0.1';

FLUSH PRIVILEGES;

USE order_fulfillment;

CREATE TABLE IF NOT EXISTS orders (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    order_no VARCHAR(64) NOT NULL,
    customer_id VARCHAR(64) NOT NULL,
    status VARCHAR(32) NOT NULL,
    amount DECIMAL(12,2) NOT NULL DEFAULT 0,
    message TEXT NOT NULL,
    source VARCHAR(128) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uk_orders_order_no (order_no),
    KEY idx_orders_status_created_at (status, created_at),
    KEY idx_orders_customer_created_at (customer_id, created_at),
    KEY idx_orders_source_created_at (source, created_at)
);
