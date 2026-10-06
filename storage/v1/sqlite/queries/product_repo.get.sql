SELECT product_repo_id
FROM product_repo
WHERE product_id = :product_id
  AND repo_id = :repo_id
  AND ref = :ref;
