INSERT INTO traust_storage.product (
    slug,
    segment,
    registered_at
)
VALUES (
    %(slug)s,
    %(segment)s,
    %(registered_at)s
)
ON CONFLICT (slug) DO UPDATE SET
    segment = EXCLUDED.segment;
