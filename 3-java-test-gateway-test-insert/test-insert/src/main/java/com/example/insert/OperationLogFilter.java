package com.example.insert;

import java.io.IOException;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

@Component
class OperationLogFilter extends OncePerRequestFilter {
    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain filterChain)
            throws ServletException, IOException {
        OperationLog.Span span = OperationLog.startServerSpan(request.getMethod() + " " + request.getRequestURI());
        try {
            filterChain.doFilter(request, response);
        } catch (ServletException | IOException | RuntimeException error) {
            span.close(error);
            throw error;
        }
        span.close();
    }
}
