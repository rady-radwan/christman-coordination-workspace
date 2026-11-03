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
3. Ball with several trades, coordination meetings with PDF minutes, coordination schedule, project status bar — version 0.3
4. Next-meeting agenda and prep list, BIM Execution Plan with files, Excel clash reports viewer — version 0.4
5. **Announcements, Word-like BEP sections and Word import, Excel-style clash sheets, notification clean-up, new-version alert** ← version 0.5
   Still to come: voice messages, PDF attachments, sign-off matrix, model tracker, dashboard, reports, email alerts
6. Android release
7. iOS

## Builds

Pushing to `main` makes GitHub Actions analyze and test the code, build the Windows installer
(Inno Setup, no admin rights needed) and the Android APKs, and save them on the `installer` branch
together with `version.json`. Installed apps read `version.json` and offer the new version
(with the points for that version from `WHATS-NEW.md`) and a download button.

To release a new version: bump `version:` in `pubspec.yaml` and `appVersion` in `lib/config.dart`,
add a section to `WHATS-NEW.md`, and push to `main`.

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
