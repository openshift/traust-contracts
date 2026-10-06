SELECT product_repo_id
FROM traust_storage.product_repo
WHERE product_id = %(product_id)s
  AND repo_id = %(repo_id)s
  AND ref = %(ref)s;
