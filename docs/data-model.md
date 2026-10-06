# Data model

How the storage and ledger tables relate. The SQL under `storage/v1/` and
`ledger/v1/` is the source of truth; these diagrams show the shape. Keys:
`PK` primary key, `FK` foreign key, `UK` unique (natural key).

## From folders to tables

What used to be a folder convention on disk (`findings/<product>/<repo>/`) is
relational: every artifact is filed under a registered product and repo.

```mermaid
flowchart LR
  subgraph FS[Filesystem convention]
    F1[findings] --> F2[product folder]
    F2 --> F3[repo folder]
    F3 --> F4[audit, triage, findings-current, layer files]
  end
  subgraph DB[Relational]
    D1[product] --> D2[product_repo]
    D3[repo] --> D2
    D2 --> D4[artifact_binding]
    D4 --> D5[projections: report, report_finding, triage_verdict, ...]
  end
  F2 -.->|becomes| D1
  F3 -.->|becomes| D3
  F3 -.->|product and repo pair becomes| D2
  F4 -.->|each file becomes| D4
```

## Registry and inventory

Products and repos are many-to-many. A `product_repo` is a repo as a product
ships it, at one ref (`''` = default branch, `release-5.0` = a release
branch). Inventory facts hang off it.

```mermaid
erDiagram
  product ||--o{ product_repo : ships
  repo ||--o{ product_repo : shipped_as
  product_repo ||--o{ product_repo_version : shipped_in
  product_repo ||--o{ repo_owner : owned_by

  product {
    text product_id PK
    text slug UK
    text segment
  }
  repo {
    text repo_id PK
    text repo_url UK
  }
  product_repo {
    text product_repo_id PK
    text product_id FK
    text repo_id FK
    text ref
    text sub_service
    text resource_type
  }
  product_repo_version {
    text product_repo_id PK
    text version PK
    text category
    json cluster_operators
    json images
  }
  repo_owner {
    text product_repo_id PK
    text team PK
    text manager
    json individuals
    text source
    text jira_project
    text jira_component
  }
```

| Table | Natural key (unique) | Notes |
|---|---|---|
| `product` | `slug` | `segment` = inventory grouping (openshift, operator-catalog, services, ...) |
| `repo` | `repo_url` | exact string; not canonicalized |
| `product_repo` | `(product_id, repo_id, ref)` | the owner of artifacts and ledger layers |
| `product_repo_version` | `(product_repo_id, version)` | which product versions ship it |
| `repo_owner` | `(product_repo_id, team)` | several teams may own one product_repo |

Primary keys are database identifiers (UUIDs the Store assigns).
`Store.register_*` insert or refresh by natural key and return the id;
`Store.find_product_repo(slug, repo_url, ref)` looks one up without creating it.

## Artifacts

An artifact's bytes are stored once (`artifact_evidence`, keyed by digest);
each filing of those bytes in a context is a binding; every artifact type
projects into its own table keyed by the binding.

```mermaid
erDiagram
  product_repo ||--o{ artifact_binding : owns
  artifact_binding }o--|| artifact_evidence : bytes_in
  artifact_binding ||--o{ artifact_location : stored_at
  artifact_binding ||--o| report : projects_to
  report ||--o{ report_finding : contains
  artifact_binding ||--o{ triage_verdict : projects_to
  artifact_binding ||--o{ layer_event : projects_to

  artifact_evidence {
    text digest PK
    int byte_size
  }
  artifact_binding {
    text binding_id PK
    text artifact_digest FK
    text artifact_name
    text artifact_role
    text scope_id
    text subject_id
    text run_id
    text layer_id
    text supersedes_binding_id
    text product_repo_id FK
    text commit_sha
  }
  artifact_location {
    text binding_id PK
    text reference PK
  }
  report {
    text binding_id PK
    text title
    json metadata
  }
  report_finding {
    text binding_id PK
    text finding_id PK
    text severity
    text fingerprint
    text validity
    text resolution
  }
  triage_verdict {
    text binding_id PK
    text finding_id PK
    text verdict
  }
  layer_event {
    text binding_id PK
    text event_id PK
    text finding_ref
    text validity
    text resolution
  }
```

- `binding_id` is a hash of the binding context (digest, artifact, scope,
  subject, run, layer, role), so a retry of the same filing is idempotent.
  `product_repo_id` and `commit_sha` are constrained attributes, not part of it.
- Every projection table (about 40) references `artifact_binding`; only a few
  are drawn. `profiles.json` maps each artifact to its projection.
- A `report` with role `cumulative` is the findings-current view; one chain of
  them is current per `(scope_id, product_repo_id, run_id)`.

## Ledger (optional)

The ledger records dispositions over time. It is optional; storage is always
present when a database is used, so the ledger references storage and never
the reverse (same database, storage initialized first).

```mermaid
erDiagram
  product_repo ||--o| layers : dispositions_for
  layers ||--o{ events : contains
  layers ||--o{ materialized_findings : derives

  layers {
    text layer_id PK
    text product_repo_id FK
    text repository
    text merkle_root
  }
  events {
    bigint id PK
    text layer_id FK
    int seq
    text event_id
    text finding_ref
    text validity
    text resolution
  }
  materialized_findings {
    text layer_id PK
    text finding_ref PK
    text validity
    text resolution
  }
```

`layers.product_repo_id` is unique when set: one layer per product_repo.
Events are append-only (`UNIQUE (layer_id, seq)`, `UNIQUE (layer_id, event_id)`).

## Joining it together

A product_repo's current findings with their disposition history:

```sql
SELECT pr.product_repo_id, rf.finding_id, rf.severity, e.recorded_at, e.validity, e.resolution
FROM traust_storage.product_repo     pr
JOIN traust_storage.artifact_binding b  ON b.product_repo_id  = pr.product_repo_id
JOIN traust_storage.report_finding   rf ON rf.binding_id      = b.binding_id
JOIN traust_ledger.layers            l  ON l.product_repo_id  = pr.product_repo_id
JOIN traust_ledger.events            e  ON e.layer_id         = l.layer_id
                                       AND e.finding_ref      = rf.finding_id;
```

`finding_id` / `finding_ref` are scoped to a report, so the finding join only
holds inside one product_repo (as above). Repos a product ships but nobody has
scanned are `product_repo` rows with no `artifact_binding`.

## Revisions

Storage and ledger schemas carry a revision (`traust_storage_meta`,
`schema_revision`); both were rebaselined to revision 1 in 0.50.0. How
revisions and `Store.migrate()` work: [storage/v1/README.md](../storage/v1/README.md),
"Compatibility" and "Migrations".
