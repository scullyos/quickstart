# Security Policy

## Reporting a vulnerability

Please **do not** open public GitHub issues for security problems.

Use **GitHub Private Vulnerability Reporting**:

1. Go to the [Security tab](https://github.com/scullyos/quickstart/security) of this repository.
2. Click **Report a vulnerability**.
3. Fill in the form. Only repository maintainers will see the report.

We aim to acknowledge new reports within **5 business days** and to provide a
remediation timeline within **15 business days** of acknowledgement.

## Scope

This repository is the **ScullyOS quickstart** — a Docker Compose bundle that
wires together prebuilt images of the ScullyOS platform microservices. It
ships configuration (compose files, env defaults, fluent-bit config, MySQL
init scripts, ES/Kibana setup scripts) but **not the source code** of those
services.

In scope for reports here:

- Misconfiguration in `docker-compose.yml`, `env/*.env`, `fluent-bit/*`,
  `mysql-init/*`, `setup/*` that creates a security weakness in a default
  quickstart deployment.
- Insecure defaults in `.env.example` (e.g. weak credentials shipped as the
  expected production value, rather than as a clearly-marked placeholder
  the user is told to replace).
- Vulnerabilities in the helper scripts under `scripts/`.

Out of scope for reports here (please file against the relevant upstream
repo instead, once those repos are public):

- Vulnerabilities in the platform images themselves (`person-ms`,
  `authorization-ms`, `bo-orc-ms`, `scullyosapp-webapp`).
- Vulnerabilities in third-party images this stack composes
  (`mysql`, `elasticsearch`, `kibana`, `fluent-bit`).

## Supported versions

Only the `master` branch is supported. Older tagged versions of the
quickstart receive no fixes — please update to the latest before
reporting.
