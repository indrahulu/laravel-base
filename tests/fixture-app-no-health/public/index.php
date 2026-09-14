<?php

$path = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/';

if ($path !== '/') {
    http_response_code(404);
    header('Content-Type: text/plain');
    echo "Not Found\n";
    return;
}

http_response_code(200);
header('Content-Type: text/plain');
echo "Fixture app without HTTP health endpoint\n";
