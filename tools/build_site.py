"""Builds the public web pages that Google Play requires a URL for.

Play will not accept an in-app screen or a file in the repository: the privacy
policy and the account-deletion instructions both have to be a page anyone can
open without signing in. This turns the two Markdown policies that already live
at the repository root into styled HTML, adds the deletion page whose text lives
below, writes the lot into `site/` for `firebase deploy --only hosting`, and
generates the plain-text copy shown inside the Flutter app.

The policies stay the single source of truth — edit the Markdown, re-run this,
test, deploy.

    python tools/build_site.py
    firebase deploy --only hosting --project shadchan-gilad
"""

from __future__ import annotations

import html
import re
from pathlib import Path

import markdown

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "site"

CONTACT = "giladsh22@gmail.com"
DEVELOPER = "גלעד שטרוזמן"

# Shared stylesheet. Inlined into every page rather than linked, because four
# small pages that each stand alone beat four pages that break together.
CSS = """
:root {
  --bg: #f7f5fb;
  --card: #ffffff;
  --ink: #1c1b22;
  --muted: #5d5a6b;
  --line: #e4e0ee;
  --accent: #6b4ea8;
  --accent-soft: #f0ebfa;
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #16151c;
    --card: #1f1e27;
    --ink: #ecebf2;
    --muted: #a8a4b8;
    --line: #322f3d;
    --accent: #b49ae6;
    --accent-soft: #272335;
  }
}
* { box-sizing: border-box; }
body {
  margin: 0;
  padding: 0 20px 72px;
  background: var(--bg);
  color: var(--ink);
  font-family: "Segoe UI", Rubik, Arial, sans-serif;
  font-size: 17px;
  line-height: 1.75;
  -webkit-text-size-adjust: 100%;
}
main {
  max-width: 760px;
  margin: 0 auto;
  background: var(--card);
  border: 1px solid var(--line);
  border-radius: 18px;
  padding: 40px 34px 48px;
  margin-top: 32px;
}
header.site {
  max-width: 760px;
  margin: 0 auto;
  padding: 26px 4px 0;
  display: flex;
  flex-wrap: wrap;
  gap: 8px 18px;
  align-items: baseline;
}
header.site .brand {
  font-size: 20px;
  font-weight: 700;
  color: var(--accent);
  text-decoration: none;
}
header.site nav a {
  color: var(--muted);
  text-decoration: none;
  font-size: 15px;
}
header.site nav a:hover { color: var(--accent); text-decoration: underline; }
header.site nav { display: flex; gap: 16px; flex-wrap: wrap; }
h1 {
  font-size: 30px;
  line-height: 1.3;
  margin: 0 0 6px;
  color: var(--accent);
}
h2 {
  font-size: 21px;
  margin: 38px 0 12px;
  padding-top: 18px;
  border-top: 1px solid var(--line);
}
h2:first-of-type { border-top: 0; padding-top: 0; }
h3 { font-size: 18px; margin: 26px 0 8px; }
p, li { color: var(--ink); }
a { color: var(--accent); }
ul, ol { padding-inline-start: 24px; }
li { margin: 6px 0; }
hr { border: 0; border-top: 1px solid var(--line); margin: 34px 0; }
code {
  background: var(--accent-soft);
  padding: 1px 6px;
  border-radius: 6px;
  font-size: 15px;
}
table { border-collapse: collapse; width: 100%; margin: 18px 0; font-size: 15px; }
th, td { border: 1px solid var(--line); padding: 8px 10px; text-align: start; }
th { background: var(--accent-soft); }
.updated { color: var(--muted); font-size: 15px; margin: 0 0 28px; }
.note {
  background: var(--accent-soft);
  border-inline-start: 4px solid var(--accent);
  border-radius: 10px;
  padding: 14px 18px;
  margin: 22px 0;
}
.note p:first-child { margin-top: 0; }
.note p:last-child { margin-bottom: 0; }
.cards { display: grid; gap: 14px; margin-top: 26px; }
.cards a {
  display: block;
  border: 1px solid var(--line);
  border-radius: 14px;
  padding: 18px 20px;
  text-decoration: none;
  color: var(--ink);
  background: var(--bg);
}
.cards a:hover { border-color: var(--accent); }
.cards strong { display: block; color: var(--accent); font-size: 18px; margin-bottom: 2px; }
.cards span { color: var(--muted); font-size: 15px; }
footer.site {
  max-width: 760px;
  margin: 26px auto 0;
  padding: 0 4px;
  color: var(--muted);
  font-size: 14px;
}
@media (max-width: 620px) {
  body { padding: 0 14px 56px; font-size: 16px; }
  main { padding: 28px 20px 36px; border-radius: 14px; margin-top: 20px; }
  h1 { font-size: 25px; }
}
"""

NAV_HE = [
    ("index.html", "ראשי"),
    ("privacy.html", "מדיניות פרטיות"),
    ("delete-account.html", "מחיקת חשבון ונתונים"),
    ("privacy-en.html", "English"),
]

NAV_EN = [
    ("index.html", "Home"),
    ("privacy-en.html", "Privacy policy"),
    ("delete-account.html", "Delete account & data"),
    ("privacy.html", "עברית"),
]


def page(*, title: str, body: str, lang: str, description: str) -> str:
    """Wraps rendered body HTML in the shared shell."""
    rtl = lang == "he"
    nav = NAV_HE if rtl else NAV_EN
    links = "\n".join(
        f'      <a href="{href}">{html.escape(label)}</a>' for href, label in nav
    )
    return f"""<!doctype html>
<html lang="{lang}" dir="{'rtl' if rtl else 'ltr'}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(title)}</title>
<meta name="description" content="{html.escape(description)}">
<style>{CSS}</style>
</head>
<body>
  <header class="site">
    <a class="brand" href="index.html">{'שדכן' if rtl else 'Shadchan'}</a>
    <nav>
{links}
    </nav>
  </header>
  <main>
{body}
  </main>
  <footer class="site">
    {'שדכן' if rtl else 'Shadchan'} &middot; {html.escape(DEVELOPER) if rtl else 'Gilad Shtruzman'}
    &middot; <a href="mailto:{CONTACT}">{CONTACT}</a>
  </footer>
</body>
</html>
"""


def render(md_text: str) -> str:
    """Markdown to HTML, with the tables and line breaks the policies use."""
    return markdown.markdown(
        md_text,
        extensions=["tables", "sane_lists", "attr_list"],
    )


def strip_repo_links(md_text: str) -> str:
    """Drops the cross-links between the two Markdown files.

    They point at paths in the repository, which mean nothing on the web. The
    header of every page already carries a link to the other language.
    """
    md_text = re.sub(r"\[([^\]]+)\]\(PRIVACY_POLICY(?:_EN)?\.md\)", r"\1", md_text)
    return md_text


def plain_text(md_text: str) -> str:
    """Makes the readable, link-free text used by the in-app policy page."""
    text = strip_repo_links(md_text)
    text = re.sub(r"^#{1,6}\s+", "", text, flags=re.MULTILINE)
    text = re.sub(r"\[([^\]]+)\]\([^\)]+\)", r"\1", text)
    text = text.replace("**", "").replace("`", "")
    return text.strip()


def write_app_policy(he: str, en: str) -> None:
    """Writes Dart from the canonical Markdown without hand-maintained drift."""
    for label, value in (("Hebrew", he), ("English", en)):
        if "'''" in value or "${" in value:
            raise ValueError(f"{label} policy cannot be embedded in Dart")
    dart = f"""// GENERATED by tools/build_site.py from the two policy Markdown files.
// Edit PRIVACY_POLICY.md / PRIVACY_POLICY_EN.md and run the generator.
abstract final class PrivacyPolicyText {{
  static const String toEnglishLabel = 'English';
  static const String toHebrewLabel = 'עברית';
  static const String hebrewTitle = 'מדיניות פרטיות';
  static const String englishTitle = 'Privacy Policy';

  static const String hebrew = '''
{plain_text(he)}
''';

  static const String english = '''
{plain_text(en)}
''';
}}
"""
    path = ROOT / "lib" / "utils" / "privacy_policy_text.dart"
    path.write_text(dart, encoding="utf-8")
    print(f"  {path.relative_to(ROOT)}  ({len(dart):,} bytes)")


DELETE_HE = f"""
# מחיקת חשבון ונתונים — אפליקציית שדכן

הדף הזה מסביר איך למחוק את החשבון שלכם באפליקציית **שדכן** ואת הנתונים
המשויכים אליו.

**האפליקציה:** שדכן (Shadchan)
**המפתח:** {DEVELOPER}
**ליצירת קשר:** [{CONTACT}](mailto:{CONTACT})

## מחיקה מתוך האפליקציה

חשבון הוא חובה, והאפליקציה מאפשרת למחוק אותו בלי לשלוח הודעה ובלי להמתין
לטיפול ידני:

1. פתחו **הפרופיל שלי**.
2. באזור **חשבון**, לחצו **מחיקת החשבון והנתונים**.
3. קראו את האזהרה ואשרו.
4. אמתו מחדש באמצעות Google או Apple, או הקלידו את הסיסמה בחשבון דוא"ל.

המחיקה מתחילה מיד ואינה הפיכה. בחשבון Apple האפליקציה מקבלת קוד הרשאה חדש
ומבטלת גם את אסימוני Sign in with Apple.

## מחיקת נתוני שרת בלי למחוק את החשבון

זו הדרך המהירה, והיא אינה דורשת לפנות אלינו. **אפשר למחוק בה את הנתונים
שנשמרו בשרת ולהמשיך להשתמש באפליקציה ובחשבון כרגיל** — מחיקת החשבון היא
פעולה נפרדת.

1. פתחו את האפליקציה ועברו למסך **„פרטיות והמאגר שלי”**.
2. לחצו על **„מחיקת הנתונים שלי מהקהילה”** כדי להסיר מהשרת את מוני הפעילות
   שלכם ואת השם והתמונה שהופיעו בדירוג.
3. לחצו על **„מחיקת הגיבוי בענן”** כדי להסיר מהשרת את כל הרשומות, הפרופיל
   וכל התמונות שגובו.

שתי הפעולות פועלות מיד, ואינן נוגעות במאגר ששמור אצלכם במכשיר.

## אם אין לכם גישה לאפליקציה

שלחו דוא"ל אל [{CONTACT}](mailto:{CONTACT}) עם הנושא **„מחיקת חשבון”** וכתובת
הדוא"ל שאיתה נכנסתם. נאמת שהבקשה מגיעה מבעל החשבון לפני ביצוע המחיקה.

## מה נמחק

- **חשבון ההתחברות** — הרשומה שלכם בשירות ההזדהות, לרבות כתובת הדוא"ל
  ומזהה החשבון.
- **הגיבוי בענן** — כל רשומות האנשים, ההצעות, ההערות והפרופיל, וכל קובצי
  התמונות שגובו.
- **נתוני הקהילה** — מוני הפעילות, והשם והתמונה שהופיעו בדירוג.
- **הודעות אירוסין, ברכות ממתינות וטיפים לקהילה** המשויכים לחשבון.
- **המאגר המקומי במכשיר** — אנשים, רעיונות, הערות, תמונות והפרופיל.

## מה לא נמחק, ולמה

- **קובצי גיבוי שייצאתם בעצמכם** לאחסון או לאפליקציה אחרת. אלה מחוץ לשליטתנו,
  ויש למחוק אותם במקום שבו שמרתם אותם.
- **פניות תמיכה ושרשורי תגובות** — נשמרים כל עוד הם דרושים לטיפול, לתיעוד
  תקלות, לאבטחה ולמניעת שימוש לרעה. אפשר לבקש מחיקה מוקדמת בדוא"ל.
- מידע ש-Firebase Authentication מחזיקה במערכות גיבוי עשוי להימחק סופית בתוך
  עד 180 יום, לפי מדיניות השמירה של Firebase.

מעבר לאמור לעיל, לא נשמרים אצלנו נתונים לאחר המחיקה.

## שאלות

לכל שאלה בנושא: [{CONTACT}](mailto:{CONTACT}).
מידע מלא על עיבוד המידע נמצא ב[מדיניות הפרטיות](privacy.html).

---

## Account and data deletion — Shadchan (English)

**App:** Shadchan &middot; **Developer:** Gilad Shtruzman &middot;
**Contact:** [{CONTACT}](mailto:{CONTACT})

Shadchan is a local-first app with a required account and automatic cloud
backup. The active database remains on your device and works offline after
sign-in.

**To delete your account in the app:** open *My profile*, find *Account*, tap
*Delete account and data*, confirm, then reauthenticate with Google, Apple or
your password. The operation starts immediately and cannot be undone. Apple
tokens are revoked for Apple-linked accounts.

If you no longer have app access, email [{CONTACT}](mailto:{CONTACT}) with the
subject **"Delete account"** and the address you used. We verify ownership
before deletion.

**Deleted:** the authentication account (including email address and account
id); the cloud backup (all person, idea, note and profile records, and every
backed-up photo file); community data and public avatar; engagement
announcements; pending congratulations; community tips; and the local database.

**Not deleted automatically:** files you exported to other storage, and support
requests and reply threads retained as needed for support, security and abuse
prevention. You may request early deletion by email. Firebase Authentication
may take up to 180 days to remove deleted authentication data from live and
backup systems.
"""

INDEX_HE = f"""
# שדכן

אפליקציית שדכן מסייעת בניהול חברים, רעיונות, הערות ותזכורות הקשורות לתהליך
השידוכים. חשבון הוא חובה, המאגר הפעיל שמור במכשיר, וגיבוי מוצפן בתעבורה נשמר
אוטומטית בענן כדי לאפשר שחזור.

הדף הזה מרכז את המסמכים הפומביים של האפליקציה.

<div class="cards">
  <a href="privacy.html"><strong>מדיניות פרטיות</strong><span>איזה מידע האפליקציה מעבדת, היכן הוא נשמר ומה השליטה שלכם עליו</span></a>
  <a href="delete-account.html"><strong>מחיקת חשבון ונתונים</strong><span>איך מוחקים את החשבון ואת הנתונים המשויכים אליו</span></a>
  <a href="privacy-en.html"><strong>Privacy policy (English)</strong><span>The full privacy policy in English</span></a>
</div>

## יצירת קשר

{DEVELOPER} — [{CONTACT}](mailto:{CONTACT})
"""


def write(name: str, contents: str) -> None:
    path = OUT / name
    path.write_text(contents, encoding="utf-8")
    print(f"  {path.relative_to(ROOT)}  ({len(contents):,} bytes)")


def main() -> None:
    OUT.mkdir(exist_ok=True)
    print("building site/")

    he = strip_repo_links((ROOT / "PRIVACY_POLICY.md").read_text(encoding="utf-8"))
    en = strip_repo_links((ROOT / "PRIVACY_POLICY_EN.md").read_text(encoding="utf-8"))

    write_app_policy(he, en)

    write(
        "index.html",
        page(
            title="שדכן",
            body=render(INDEX_HE),
            lang="he",
            description="אפליקציית שדכן — מדיניות פרטיות ומחיקת חשבון ונתונים.",
        ),
    )
    write(
        "privacy.html",
        page(
            title="מדיניות פרטיות — שדכן",
            body=render(he),
            lang="he",
            description="מדיניות הפרטיות של אפליקציית שדכן.",
        ),
    )
    write(
        "privacy-en.html",
        page(
            title="Privacy Policy — Shadchan",
            body=render(en),
            lang="en",
            description="The privacy policy of the Shadchan application.",
        ),
    )
    write(
        "delete-account.html",
        page(
            title="מחיקת חשבון ונתונים — שדכן",
            body=render(DELETE_HE),
            lang="he",
            description="איך למחוק את החשבון באפליקציית שדכן ואת הנתונים המשויכים אליו.",
        ),
    )

    print("done. deploy with:")
    print("  firebase deploy --only hosting --project shadchan-gilad")


if __name__ == "__main__":
    main()
