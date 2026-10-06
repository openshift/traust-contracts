SELECT pr.product_repo_id
FROM product_repo pr
JOIN product p ON p.product_id = pr.product_id
JOIN repo r ON r.repo_id = pr.repo_id
WHERE p.slug = :slug
  AND r.repo_url = :repo_url
  AND pr.ref = :ref;
