'use client';

import { useRouter } from 'next/navigation';
import { useEffect, useState } from 'react';
import { useStore } from '@/data/store';
import { AUTH_ERROR_TEXT, authErrorCode, firebaseConfigured, resetPassword, signInApple, signInEmail, signInGoogle } from '@/data/firebase';
import { Button } from '@/components/ui';

function GoogleMark() {
  return (
    <svg width="18" height="18" viewBox="0 0 48 48" aria-hidden>
      <path fill="#FFC107" d="M43.6 20.5H42V20H24v8h11.3C33.7 32.7 29.2 36 24 36c-6.6 0-12-5.4-12-12s5.4-12 12-12c3.1 0 5.8 1.2 7.9 3.1l5.7-5.7C34 6.1 29.3 4 24 4 12.9 4 4 12.9 4 24s8.9 20 20 20 20-8.9 20-20c0-1.3-.1-2.4-.4-3.5z" />
      <path fill="#FF3D00" d="m6.3 14.7 6.6 4.8C14.7 15.1 19 12 24 12c3.1 0 5.8 1.2 7.9 3.1l5.7-5.7C34 6.1 29.3 4 24 4 16.3 4 9.7 8.3 6.3 14.7z" />
      <path fill="#4CAF50" d="M24 44c5.2 0 9.9-2 13.4-5.2l-6.2-5.2C29.2 35.1 26.7 36 24 36c-5.2 0-9.6-3.3-11.3-8l-6.5 5C9.5 39.6 16.2 44 24 44z" />
      <path fill="#1976D2" d="M43.6 20.5H42V20H24v8h11.3c-.8 2.2-2.2 4.2-4.1 5.6l6.2 5.2C37 39.2 44 34 44 24c0-1.3-.1-2.4-.4-3.5z" />
    </svg>
  );
}

function AppleMark() {
  return (
    <svg width="16" height="18" viewBox="0 0 384 512" aria-hidden fill="currentColor">
      <path d="M318.7 268.7c-.2-36.7 16.4-64.4 50-84.8-18.8-26.9-47.2-41.7-84.7-44.6-35.5-2.8-74.3 20.7-88.5 20.7-15 0-49.4-19.7-76.4-19.7C63.3 141.2 4 184.8 4 273.5q0 39.3 14.4 81.2c12.8 36.7 59 126.7 107.2 125.2 25.2-.6 43-17.9 75.8-17.9 31.8 0 48.3 17.9 76.4 17.9 48.6-.7 90.4-82.5 102.6-119.3-65.2-30.7-61.7-90-61.7-91.9zm-56.6-164.2c27.3-32.4 24.8-61.9 24-72.5-24.1 1.4-52 16.4-67.9 34.9-17.5 19.8-27.8 44.3-25.6 71.9 26.1 2 49.9-11.4 69.5-34.3z" />
    </svg>
  );
}

export default function LoginPage() {
  const { signIn, session } = useStore();
  const router = useRouter();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [notice, setNotice] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  // A real sign-in lands here through Firebase's listener; go in as soon as it does.
  useEffect(() => {
    if (session.signedIn) router.replace('/');
  }, [session.signedIn, router]);

  const enterDemo = () => {
    signIn('demo');
    router.replace('/');
  };

  const run = async (fn: () => Promise<unknown>) => {
    if (!firebaseConfigured) {
      setNotice('ההתחברות לחשבון האמיתי עוד לא הוגדרה באתר הזה. בינתיים אפשר להיכנס עם נתוני הדוגמה.');
      return;
    }
    setBusy(true);
    setNotice(null);
    try {
      await fn();
    } catch (e) {
      const code = authErrorCode(e);
      if (code !== 'popup-closed') setNotice(AUTH_ERROR_TEXT[code]);
    } finally {
      setBusy(false);
    }
  };

  const forgot = () => {
    if (!email.trim()) {
      setNotice('כתבו קודם את כתובת המייל, ונשלח אליה קישור לאיפוס.');
      return;
    }
    void run(async () => {
      await resetPassword(email);
      setNotice('שלחנו קישור לאיפוס הסיסמה לכתובת המייל.');
    });
  };

  return (
    <div className="grid min-h-dvh grid-cols-1 bg-page lg:grid-cols-[1fr_1.1fr]">
      <div className="flex items-center justify-center px-6 py-12">
        <div className="w-full max-w-[400px]">
          <div className="mb-8 flex items-center gap-3">
            <span className="flex h-12 w-12 items-center justify-center rounded-2xl bg-primary">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src="/logo-mark.png" alt="" className="h-8 w-8" />
            </span>
            <div>
              <div className="text-[28px] font-extrabold leading-none text-heading">שדכן</div>
              <div className="mt-1 text-[14px] text-muted">יומן אישי לניהול שידוכים</div>
            </div>
          </div>

          <h1 className="text-[24px] font-extrabold text-heading">כניסה לחשבון</h1>
          <p className="mt-1 mb-6 text-[15px] text-muted">אותו חשבון כמו באפליקציה — אותו מאגר, מסונכרן בין הטלפון למחשב.</p>

          <div className="flex flex-col gap-2.5">
            <Button className="h-12 w-full" disabled={busy} onClick={() => run(signInGoogle)}>
              <GoogleMark /> המשך עם Google
            </Button>
            <Button className="h-12 w-full !bg-black !text-white hover:!brightness-125" disabled={busy} onClick={() => run(signInApple)}>
              <AppleMark /> המשך עם Apple
            </Button>
          </div>

          <div className="my-5 flex items-center gap-3 text-[13px] text-muted">
            <span className="h-px flex-1 bg-outline" />
            או עם כתובת מייל
            <span className="h-px flex-1 bg-outline" />
          </div>

          <form
            className="flex flex-col gap-2.5"
            onSubmit={(e) => {
              e.preventDefault();
              if (!email.trim() || !password) {
                setNotice('צריך כתובת מייל וסיסמה');
                return;
              }
              void run(() => signInEmail(email, password));
            }}
          >
            <input
              type="email"
              dir="ltr"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="כתובת מייל"
              className="h-12 rounded-xl border border-outline bg-page px-4 text-[15px] outline-none focus:border-primary"
            />
            <input
              type="password"
              dir="ltr"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder="סיסמה"
              className="h-12 rounded-xl border border-outline bg-page px-4 text-[15px] outline-none focus:border-primary"
            />
            <Button variant="primary" className="h-12 w-full" type="submit" disabled={busy}>
              כניסה
            </Button>
            <button type="button" className="text-[13px] text-muted hover:underline" onClick={forgot}>
              שכחתי סיסמה
            </button>
            <p className="text-center text-[13px] text-muted">אין לך חשבון? פותחים אותו באפליקציה, ואז נכנסים כאן עם אותם פרטים.</p>
          </form>

          {notice && <p className="mt-4 rounded-xl bg-soft-yellow/60 px-4 py-3 text-[14px] text-copper-ink">{notice}</p>}

          <div className="mt-8 rounded-2xl border border-dashed border-copper/60 bg-cream p-4">
            <p className="text-[14px] font-bold text-heading">רוצה רק להסתכל?</p>
            <p className="mt-0.5 mb-3 text-[13px] text-muted">כניסה עם מאגר לדוגמה. כל השמות והפרטים בדויים, ושום דבר לא נשמר.</p>
            <Button variant="copper" className="w-full" onClick={enterDemo}>
              כניסה עם נתוני דוגמה
            </Button>
          </div>
        </div>
      </div>

      <div className="relative hidden overflow-hidden bg-cream lg:block">
        <div className="absolute inset-0 bg-[radial-gradient(circle_at_70%_25%,#d7e4ea_0,transparent_55%),radial-gradient(circle_at_20%_80%,#efdde4_0,transparent_50%)]" />
        <div className="relative flex h-full flex-col justify-center gap-6 px-16">
          <h2 className="max-w-[460px] text-[34px] font-extrabold leading-tight text-heading">
            כל המאגר שלך, על מסך גדול.
          </h2>
          <ul className="flex max-w-[460px] flex-col gap-3 text-[16px] text-body">
            <li>· רשימה, כרטיס ורעיונות — זה לצד זה</li>
            <li>· טבלה רחבה עם סינון ומיון לכל המאגר</li>
            <li>· חיפוש מהיר בכל דבר עם Ctrl K</li>
            <li>· כל שינוי מגיע לטלפון, וכל שינוי בטלפון מגיע לכאן</li>
          </ul>
          <div className="mt-4 flex gap-4">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src="/add_friends_art.png" alt="" className="h-28 w-28 object-contain opacity-90" />
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src="/add_idea_art.png" alt="" className="h-28 w-28 object-contain opacity-90" />
          </div>
        </div>
      </div>
    </div>
  );
}
