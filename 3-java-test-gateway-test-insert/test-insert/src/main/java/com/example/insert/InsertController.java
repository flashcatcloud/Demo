package com.example.insert;

import java.time.Instant;
import java.util.Map;

import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api")
class InsertController {
    private final InsertService insertService;

    InsertController(InsertService insertService) {
        this.insertService = insertService;
    }

    @PostMapping("/insert")
    Map<String, Object> insert(@RequestBody InsertRequest request) {
        return createOrder(request);
    }

    @PostMapping("/orders")
    Map<String, Object> createOrder(@RequestBody InsertRequest request) {
        long id = insertService.insert(request);
        return Map.of("id", id, "status", "inserted", "receivedAt", Instant.now().toString());
    }

    @PutMapping("/orders/{id}/status")
    Map<String, Object> updateStatus(@PathVariable("id") long id, @RequestBody InsertRequest request) {
        int rows = insertService.updateStatus(id, request);
        return Map.of("id", id, "updated", rows, "status", rows == 1 ? "updated" : "not_found",
                "receivedAt", Instant.now().toString());
    }

    @DeleteMapping("/orders/{id}")
    Map<String, Object> delete(@PathVariable("id") long id) {
        int rows = insertService.delete(id);
        return Map.of("id", id, "deleted", rows, "status", rows == 1 ? "deleted" : "not_found",
                "receivedAt", Instant.now().toString());
    }
}
