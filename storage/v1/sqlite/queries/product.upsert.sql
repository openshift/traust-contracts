INSERT INTO product (
    product_id,
    slug,
    segment,
    registered_at
)
VALUES (
    :product_id,
    :slug,
    :segment,
    :registered_at
)
ON CONFLICT (slug) DO UPDATE SET
    segment = EXCLUDED.segment;
