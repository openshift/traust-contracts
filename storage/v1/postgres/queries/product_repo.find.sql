SELECT pr.product_repo_id
FROM traust_storage.product_repo pr
JOIN traust_storage.product p ON p.product_id = pr.product_id
JOIN traust_storage.repo r ON r.repo_id = pr.repo_id
WHERE p.slug = %(slug)s
  AND r.repo_url = %(repo_url)s
  AND pr.ref = %(ref)s;
