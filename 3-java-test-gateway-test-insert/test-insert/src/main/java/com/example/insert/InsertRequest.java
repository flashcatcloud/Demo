package com.example.insert;

import java.math.BigDecimal;

record InsertRequest(String orderNo, String customerId, String status, BigDecimal amount, String message, String source,
                     String sentAt) {
    String safeOrderNo() {
        return orderNo == null || orderNo.isBlank() ? "ORD-" + System.currentTimeMillis() : orderNo;
    }

    String safeCustomerId() {
        return customerId == null || customerId.isBlank() ? "customer-demo" : customerId;
    }

    String safeStatus() {
        return status == null || status.isBlank() ? "CREATED" : status;
    }

    BigDecimal safeAmount() {
        return amount == null ? BigDecimal.ZERO : amount;
    }

    String safeMessage() {
        return message == null || message.isBlank() ? "empty message" : message;
    }

    String safeSource() {
        return source == null || source.isBlank() ? "unknown" : source;
    }
}
