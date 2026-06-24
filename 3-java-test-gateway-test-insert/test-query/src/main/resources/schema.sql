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
