# Christman Coordination Workspace

BIM/MEP coordination between the Christman VDC coordinator and the trade partners on our projects.
Flutter app (Windows first, then Android and iOS) on a Supabase back end.

## Who can do what

| Role | Can do |
| --- | --- |
| **Admin** | Everything on every project: projects, trades, item types, people, approvals. |
| **Coordinator** | Create, edit, close, void, hold and reopen items; pass the ball to any trade. |
| **Trade lead** | Submit a response, mark the model updated, pass the ball while their trade holds it, suggest new team members (the admin approves). |
| **Trade member** | Submit a response, mark the model updated, pass the ball while their trade holds it. |
| **Viewer** | Read only (owner, architect). |

People only see the projects they are added to. New accounts wait for the admin's approval.
Sign-in is a 6-digit code sent by email (no passwords). The first account ever created becomes the admin.

All of these rules, plus the automatic item numbering (`NMC-CL-001`), live in the database:
[`supabase/schema.sql`](supabase/schema.sql).

## Stages

1. Accounts, projects, trades and items — version 0.1
2. Photos with markup, priority colors, themes, font and text size per person — version 0.2
3. **Ball with several trades, coordination meetings with PDF minutes, coordination schedule, project status bar** ← version 0.3
   Still to come: voice messages, PDF attachments, clash import, sign-off matrix, model tracker, dashboard, reports, email alerts
4. Android release
5. iOS

## Builds

Pushing to `main` makes GitHub Actions analyze and test the code, build the Windows installer
(Inno Setup, no admin rights needed) and the Android APKs, and save them on the `installer` branch.

## Server setup

See [`SERVER-SETUP.md`](SERVER-SETUP.md).

```
lib/
  main.dart            start-up and the sign-in / waiting / app switch
  config.dart          server address and app version
  models.dart          Item, Trade, Profile, statuses, roles…
  data/api.dart        every server call
  state/               app state, filters, settings saved on the device
  screens/             sign-in, Windows shell + phone tabs, items, item detail, forms, team, setup, settings
  widgets/common.dart  badges, chips, panels, dialogs
supabase/
  schema.sql           tables, numbering, permission rules (tested on Postgres 16)
  email-template.html  the sign-in email with the 6-digit code
```
