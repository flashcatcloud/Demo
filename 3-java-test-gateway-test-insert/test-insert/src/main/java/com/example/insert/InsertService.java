package com.example.insert;

import java.sql.PreparedStatement;
import java.sql.Statement;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.support.GeneratedKeyHolder;
import org.springframework.stereotype.Service;

@Service
class InsertService {
    private static final org.slf4j.Logger LOGGER = org.slf4j.LoggerFactory.getLogger(InsertService.class);
    private final JdbcTemplate jdbcTemplate;

    InsertService(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }

    long insert(InsertRequest request) {
        try (OperationLog.Span ignored = OperationLog.startSpan("db.insert orders")) {
            GeneratedKeyHolder keyHolder = new GeneratedKeyHolder();
            jdbcTemplate.update(connection -> {
                PreparedStatement statement = connection.prepareStatement(
                        """
                                INSERT INTO orders(order_no, customer_id, status, amount, message, source)
                                VALUES (?, ?, ?, ?, ?, ?)
                                """,
                        Statement.RETURN_GENERATED_KEYS);
                statement.setString(1, request.safeOrderNo());
                statement.setString(2, request.safeCustomerId());
                statement.setString(3, request.safeStatus());
                statement.setBigDecimal(4, request.safeAmount());
                statement.setString(5, request.safeMessage());
                statement.setString(6, request.safeSource());
                return statement;
            }, keyHolder);
            Number key = keyHolder.getKey();
            long id = key == null ? -1L : key.longValue();
            LOGGER.info("order created order_id={} order_no={} customer_id={} status={} amount={} source={} "
                            + "warehouse=shanghai-01 inventory_reservation=success payment_route=primary",
                    id, request.safeOrderNo(), request.safeCustomerId(), request.safeStatus(), request.safeAmount(),
                    request.safeSource());
            if ("PENDING_REVIEW".equalsIgnoreCase(request.safeStatus())) {
                LOGGER.warn("order entered manual review order_id={} order_no={} risk_score=87.6 threshold=80 "
                                + "matched_rules=[address_change,high_amount,new_device] suggestion=\"verify risk rule version and reviewer queue\"",
                        id, request.safeOrderNo());
            } else if ("REJECTED".equalsIgnoreCase(request.safeStatus())) {
                LOGGER.warn("order rejected order_id={} order_no={} reject_reason=\"risk control denied\" "
                                + "refund_required=false suggestion=\"sample order will be deleted by audit flow\"",
                        id, request.safeOrderNo());
            }
            return id;
        }
    }

    int updateStatus(long id, InsertRequest request) {
        try (OperationLog.Span ignored = OperationLog.startSpan("db.update order status")) {
            int rows = jdbcTemplate.update("""
                    UPDATE orders
                    SET status = ?, message = ?
                    WHERE id = ?
                    """, request.safeStatus(), request.safeMessage(), id);
            LOGGER.info("order status changed order_id={} new_status={} affected_rows={} operator=fulfillment-worker "
                            + "message=\"{}\"",
                    id, request.safeStatus(), rows, request.safeMessage());
            if ("PAID".equalsIgnoreCase(request.safeStatus())) {
                LOGGER.info("payment confirmed order_id={} payment_channel=mockpay callback_lag_ms=418 "
                                + "dedup_key=payment:order:{} suggestion=\"monitor callback retry ratio\"",
                        id, id);
            }
            return rows;
        }
    }

    int delete(long id) {
        try (OperationLog.Span ignored = OperationLog.startSpan("db.delete order")) {
            int rows = jdbcTemplate.update("DELETE FROM orders WHERE id = ?", id);
            LOGGER.warn("order deleted order_id={} affected_rows={} reason=\"audit rejected sample cleanup\" "
                            + "data_retention=not_applicable suggestion=\"confirm delete event is expected in trace\"",
                    id, rows);
            return rows;
        }
    }
}
