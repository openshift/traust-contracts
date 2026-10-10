INSERT INTO traust_storage.product (
    product_id,
    slug,
    segment,
    registered_at
)
VALUES (
    %(product_id)s,
    %(slug)s,
    %(segment)s,
    %(registered_at)s
)
ON CONFLICT (slug) DO UPDATE SET
    segment = EXCLUDED.segment;
