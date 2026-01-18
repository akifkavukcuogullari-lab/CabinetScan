/**
 * Custom hook for Google Analytics tracking in Next.js App Router
 *
 * This hook handles:
 * - Page view tracking on route changes
 * - Provides easy access to event tracking functions
 */

'use client';

import { useEffect } from 'react';
import { usePathname, useSearchParams } from 'next/navigation';
import {
  pageview,
  trackEvent,
  trackTrialSignup,
  trackDemoRequest,
  trackScanCompleted,
  trackViewPricing,
  trackBeginTrialForm,
  trackError,
} from '@/lib/analytics';

/**
 * Hook to automatically track page views on route changes
 * Add this to your root layout or a client component that wraps your app
 */
export function usePageTracking() {
  const pathname = usePathname();
  const searchParams = useSearchParams();

  useEffect(() => {
    if (pathname) {
      // Construct full URL with search params
      const url = searchParams?.toString()
        ? `${pathname}?${searchParams.toString()}`
        : pathname;

      pageview(url);
    }
  }, [pathname, searchParams]);
}

/**
 * Hook that provides all analytics tracking functions
 * Use this in components that need to track events
 */
export function useAnalytics() {
  return {
    // Generic tracking
    trackEvent,
    pageview,

    // Conversion events
    trackTrialSignup,
    trackDemoRequest,

    // Engagement events
    trackScanCompleted,

    // Funnel events
    trackViewPricing,
    trackBeginTrialForm,

    // Error tracking
    trackError,
  };
}

export default useAnalytics;
