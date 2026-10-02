-- Optimistic concurrency test for MySQL JSON Duality Views
-- Expected result: final UPDATE fails because the retained ETag is stale.

USE jdv_spike;

SET @stale_document = (
    SELECT data
    FROM order_dv
    WHERE data->'$._id' = 3
);

SELECT
    JSON_UNQUOTE(JSON_EXTRACT(@stale_document, '$._id')) AS stale_document_id,
    JSON_UNQUOTE(JSON_EXTRACT(@stale_document, '$.product')) AS stale_product,
    JSON_UNQUOTE(JSON_EXTRACT(@stale_document, '$._metadata.etag')) AS stale_etag;

UPDATE orders
SET product = 'Whole Wheat Flour'
WHERE order_id = 3;

SELECT
    order_id,
    product,
    amount
FROM orders
WHERE order_id = 3;

SELECT
    data->>'$.product' AS current_product,
    data->>'$._metadata.etag' AS current_etag
FROM order_dv
WHERE data->'$._id' = 3;

UPDATE order_dv
SET data = JSON_SET(
    @stale_document,
    '$.product',
    'Stale Client Flour'
)
WHERE data->'$._id' = 3;
