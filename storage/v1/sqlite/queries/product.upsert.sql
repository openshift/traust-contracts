INSERT INTO product (
    slug,
    segment,
    registered_at
)
VALUES (
    :slug,
    :segment,
    :registered_at
)
ON CONFLICT (slug) DO UPDATE SET
    segment = EXCLUDED.segment;
