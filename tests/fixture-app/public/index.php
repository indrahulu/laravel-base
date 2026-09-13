<?php

declare(strict_types=1);

$path = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/';

if ($path === '/up') {
    http_response_code(200);
    header('Content-Type: text/plain');
    echo "OK\n";
    return;
}

if ($path === '/health-fail') {
    http_response_code(503);
    header('Content-Type: text/plain');
    echo "Unavailable\n";
    return;
}

http_response_code(200);
header('Content-Type: text/plain');
echo "Fixture Laravel-like app\n";
