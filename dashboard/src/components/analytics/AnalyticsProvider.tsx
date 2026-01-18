/**
 * Analytics Provider Component
 *
 * This client component wraps the application to track page views
 * on route changes in Next.js App Router.
 *
 * Usage in layout.tsx:
 * ```tsx
 * import { AnalyticsProvider } from '@/components/analytics/AnalyticsProvider';
 *
 * export default function RootLayout({ children }) {
 *   return (
 *     <html>
 *       <body>
 *         <AnalyticsProvider />
 *         {children}
 *       </body>
 *     </html>
 *   );
 * }
 * ```
 */

'use client';

import { Suspense } from 'react';
import { usePageTracking } from '@/hooks/useAnalytics';

function AnalyticsTracker() {
  usePageTracking();
  return null;
}

export function AnalyticsProvider() {
  return (
    <Suspense fallback={null}>
      <AnalyticsTracker />
    </Suspense>
  );
}

export default AnalyticsProvider;
