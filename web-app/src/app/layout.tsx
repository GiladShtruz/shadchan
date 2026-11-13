import type { Metadata } from 'next';
import type { ReactNode } from 'react';
import { StoreProvider } from '@/data/store';
import { ToastProvider } from '@/components/toast';
import './globals.css';

export const metadata: Metadata = {
  title: 'שדכן – יומן אישי לניהול שידוכים',
  description: 'הממשק למחשב של אפליקציית שדכן: אותו חשבון, אותו מאגר, מסונכרן עם הטלפון.',
  icons: { icon: '/icon.png' },
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="he" dir="rtl">
      <head>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="" />
        {/* eslint-disable-next-line @next/next/no-page-custom-font */}
        <link
          href="https://fonts.googleapis.com/css2?family=Assistant:wght@400;500;600;700;800&display=swap"
          rel="stylesheet"
        />
      </head>
      <body>
        <ToastProvider>
          <StoreProvider>{children}</StoreProvider>
        </ToastProvider>
      </body>
    </html>
  );
}
