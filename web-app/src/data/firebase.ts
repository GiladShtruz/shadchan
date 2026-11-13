'use client';

import { getApps, initializeApp, type FirebaseApp } from 'firebase/app';
import { initializeAppCheck, ReCaptchaEnterpriseProvider, ReCaptchaV3Provider } from 'firebase/app-check';
import {
  browserSessionPersistence,
  connectAuthEmulator,
  getAuth,
  GoogleAuthProvider,
  OAuthProvider,
  sendPasswordResetEmail,
  setPersistence,
  signInWithEmailAndPassword,
  signInWithPopup,
  signOut as fbSignOut,
  type Auth,
} from 'firebase/auth';
import { connectFirestoreEmulator, getFirestore, type Firestore } from 'firebase/firestore';
import { connectStorageEmulator, getStorage, type FirebaseStorage } from 'firebase/storage';

/**
 * The web app's own registration in Firebase project `shadchan-gilad`.
 *
 * These values are public by design (they ship in every browser bundle);
 * what protects the data is Firebase Auth + the Firestore/Storage rules +
 * App Check. They come from Vercel environment variables so the same build
 * can be pointed at the emulators or another project.
 */
const config = {
  apiKey: process.env.NEXT_PUBLIC_FIREBASE_API_KEY,
  authDomain: process.env.NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN ?? 'shadchan-gilad.firebaseapp.com',
  projectId: process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID ?? 'shadchan-gilad',
  storageBucket: process.env.NEXT_PUBLIC_FIREBASE_STORAGE_BUCKET ?? 'shadchan-gilad.firebasestorage.app',
  messagingSenderId: process.env.NEXT_PUBLIC_FIREBASE_MESSAGING_SENDER_ID ?? '769854167286',
  appId: process.env.NEXT_PUBLIC_FIREBASE_APP_ID,
};

/** reCAPTCHA site key for App Check (Firestore and Storage enforce it). */
const recaptchaEnterpriseKey = process.env.NEXT_PUBLIC_RECAPTCHA_ENTERPRISE_KEY;
const recaptchaV3Key = process.env.NEXT_PUBLIC_RECAPTCHA_V3_KEY;

/** Whether this build can talk to the real account at all. */
export const firebaseConfigured = Boolean(config.apiKey && config.appId);

interface Handles {
  app: FirebaseApp;
  auth: Auth;
  db: Firestore;
  storage: FirebaseStorage;
}

let handles: Handles | null = null;

export function fb(): Handles {
  if (!firebaseConfigured) throw new Error('Firebase is not configured for this build');
  if (handles) return handles;
  const app = getApps()[0] ?? initializeApp(config);
  if (typeof window !== 'undefined' && (recaptchaEnterpriseKey || recaptchaV3Key)) {
    try {
      initializeAppCheck(app, {
        provider: recaptchaEnterpriseKey ? new ReCaptchaEnterpriseProvider(recaptchaEnterpriseKey) : new ReCaptchaV3Provider(recaptchaV3Key!),
        isTokenAutoRefreshEnabled: true,
      });
    } catch {
      /* already initialised (hot reload) */
    }
  }
  const auth = getAuth(app);
  // The database is private and a desktop may be shared: the session ends
  // when the browser tab closes, never "remember me" by default.
  void setPersistence(auth, browserSessionPersistence);
  const db = getFirestore(app);
  const storage = getStorage(app);
  // Local testing only: point every service at the Firebase emulators.
  if (process.env.NEXT_PUBLIC_USE_EMULATORS === '1') {
    connectAuthEmulator(auth, 'http://127.0.0.1:9099', { disableWarnings: true });
    connectFirestoreEmulator(db, '127.0.0.1', 8080);
    connectStorageEmulator(storage, '127.0.0.1', 9199);
  }
  handles = { app, auth, db, storage };
  return handles;
}

export type AuthErrorCode =
  | 'popup-closed'
  | 'wrong-password'
  | 'user-not-found'
  | 'email-in-use'
  | 'weak-password'
  | 'invalid-email'
  | 'unauthorized-domain'
  | 'network'
  | 'apple-not-ready'
  | 'unknown';

export function authErrorCode(e: unknown): AuthErrorCode {
  const code = (e as { code?: string })?.code ?? '';
  if (code.includes('popup-closed') || code.includes('cancelled-popup')) return 'popup-closed';
  if (code.includes('wrong-password') || code.includes('invalid-credential') || code.includes('invalid-login')) return 'wrong-password';
  if (code.includes('user-not-found')) return 'user-not-found';
  if (code.includes('email-already-in-use')) return 'email-in-use';
  if (code.includes('weak-password')) return 'weak-password';
  if (code.includes('invalid-email')) return 'invalid-email';
  if (code.includes('unauthorized-domain')) return 'unauthorized-domain';
  if (code.includes('network')) return 'network';
  if (code.includes('operation-not-allowed') || code.includes('invalid-oauth')) return 'apple-not-ready';
  return 'unknown';
}

export const AUTH_ERROR_TEXT: Record<AuthErrorCode, string> = {
  'popup-closed': 'חלון ההתחברות נסגר לפני שהסתיים',
  'wrong-password': 'כתובת המייל או הסיסמה לא נכונים',
  'user-not-found': 'אין חשבון עם הכתובת הזו',
  'email-in-use': 'לכתובת הזו כבר יש חשבון — אפשר להתחבר אליו',
  'weak-password': 'הסיסמה קצרה מדי (לפחות 6 תווים)',
  'invalid-email': 'כתובת המייל לא תקינה',
  'unauthorized-domain': 'הכתובת של האתר עוד לא אושרה בהגדרות ההתחברות',
  network: 'אין חיבור לאינטרנט',
  'apple-not-ready': 'ההתחברות עם Apple עוד לא זמינה באתר. אפשר להתחבר עם Google או מייל.',
  unknown: 'ההתחברות לא הצליחה. כדאי לנסות שוב.',
};

export async function signInGoogle() {
  const { auth } = fb();
  const provider = new GoogleAuthProvider();
  provider.setCustomParameters({ prompt: 'select_account' });
  return signInWithPopup(auth, provider);
}

export async function signInApple() {
  const { auth } = fb();
  const provider = new OAuthProvider('apple.com');
  provider.addScope('email');
  provider.addScope('name');
  return signInWithPopup(auth, provider);
}

export async function signInEmail(email: string, password: string) {
  return signInWithEmailAndPassword(fb().auth, email.trim(), password);
}

export async function resetPassword(email: string) {
  return sendPasswordResetEmail(fb().auth, email.trim());
}

export async function signOutFirebase() {
  if (!firebaseConfigured) return;
  await fbSignOut(fb().auth);
}
