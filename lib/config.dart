/// The company's Coordination Workspace server (Supabase).
/// The publishable key is meant to ship inside apps; the database's security
/// rules (supabase/schema.sql) decide what each person can see and change.
const serverUrl = 'https://uyihedpnoputpxvueyol.supabase.co';
const serverKey = 'sb_publishable_QPloC9N0iHlizOwm8SqcMQ_Pzjyot5e';

/// Clicking the link in the sign-in email opens the app through this address.
/// The Windows installer and the Android app register it; it must also be listed
/// under Supabase > Authentication > URL Configuration > Redirect URLs.
const signInRedirect = 'christman-coord://login-callback';

const appName = 'Christman Coordination Workspace';
const appVersion = '0.2.0';
