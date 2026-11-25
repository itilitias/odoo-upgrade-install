# Third-party notices / Tredjepartsprogramvare

This product runs and bundles open-source software. It is not modified by us unless stated. The source code of each project is available from the links below. Licenses are as stated by each project: check the project for the authoritative text.

| Component | Used for | License (per project) | Source |
|---|---|---|---|
| Odoo Community | Runs the upgrade steps and customer instances | LGPL-3.0 | https://github.com/odoo/odoo |
| OCA OpenUpgrade | Migration scripts, run as a separate Odoo process (`--upgrade-path`) | AGPL-3.0 | https://github.com/OCA/OpenUpgrade |
| openupgradelib | Helper library used by OpenUpgrade scripts | AGPL-3.0 | https://github.com/OCA/openupgradelib |
| odoo-module-migrator | Porting of custom modules, run as a separate program | AGPL-3.0 | https://github.com/OCA/odoo-module-migrator |
| PostgreSQL | Database | PostgreSQL License | https://www.postgresql.org |
| Caddy | Reverse proxy and HTTPS | Apache-2.0 | https://github.com/caddyserver/caddy |
| FastAPI, Uvicorn, Jinja2, psycopg and others | The panel itself | MIT / BSD / LGPL | see `panel/requirements.txt` |

The panel does not import OpenUpgrade or the OCA tools into its own code: they are started as separate programs and only their output is read. "Odoo" is a trademark of Odoo S.A.; this product is not affiliated with or endorsed by Odoo S.A.
