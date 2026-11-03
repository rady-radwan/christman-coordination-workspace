# Server setup (Supabase)

Project: **christman-coordination-workspace** (`uyihedpnoputpxvueyol`, region us-east-2).

## 1. Database — done

Already installed on the project. To set up a fresh project, run these files in order in
**SQL Editor > New query** (each is safe to run again):

1. `supabase/schema.sql` — tables, numbering, permission rules
2. `supabase/update-2-photos-and-preferences.sql` — photos (private `files` storage) and each person's look
3. `supabase/update-3-ball-meetings-schedule.sql` — ball with several trades, meetings, schedule, coordination dates
4. `supabase/update-4-agenda-bep-clash-reports.sql` — meeting agenda and prep list, BEP, clash reports; meetings and schedule editing for admins only

## 2. Sign-in email (6-digit code)

Supabase dashboard > **Authentication**:

1. **Emails > Templates**: open **Confirm signup**, set the subject to
   `Your Coordination Workspace sign-in code`, and replace the body with the contents of
   `supabase/email-template.html`. Save. Do the same for **Magic Link**.
2. **Sign In / Providers > Email**: make sure **Email OTP Length** is **6**.
3. **URL Configuration > Redirect URLs**: add `christman-coord://login-callback`.

## 3. Sending emails to people outside your Supabase team

Supabase's built-in email only reaches members of your own Supabase organization and only a few
emails per hour. Before trades sign in, connect Resend:

1. Christman IT adds the 3 DNS records Resend gives for the sending domain.
2. Supabase > **Authentication > Emails > SMTP Settings**: turn on custom SMTP with
   host `smtp.resend.com`, port `465`, user `resend`, password = the Resend API key,
   sender e.g. `coordination@christmanco.com`, name `Christman Coordination`.

## 4. Free plan note

The free plan pauses a project after 7 days without use. Upgrade to Pro before the trades rely on it.
