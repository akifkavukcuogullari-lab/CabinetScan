/**
 * Google Analytics 4 Tracking Utilities for CabinetScan
 *
 * This module provides type-safe event tracking functions for GA4.
 * All events are designed to track the CabinetScan user journey from
 * initial visit through trial signup and room scanning.
 */

export const GA_MEASUREMENT_ID = process.env.NEXT_PUBLIC_GA_MEASUREMENT_ID;

// Type guard to check if gtag is available
const isGtagAvailable = (): boolean => {
  return typeof window !== 'undefined' && typeof window.gtag === 'function';
};

/**
 * Track page views - called automatically by Next.js route changes
 */
export const pageview = (url: string, title?: string) => {
  if (!isGtagAvailable() || !GA_MEASUREMENT_ID) return;

  window.gtag('config', GA_MEASUREMENT_ID, {
    page_path: url,
    page_title: title || document.title,
  });
};

/**
 * Generic event tracking function
 */
export const trackEvent = ({
  action,
  category,
  label,
  value,
}: {
  action: string;
  category: string;
  label?: string;
  value?: number;
}) => {
  if (!isGtagAvailable()) return;

  window.gtag('event', action, {
    event_category: category,
    event_label: label,
    value: value,
  });
};

// ============================================
// CONVERSION EVENTS (High Priority)
// ============================================

/**
 * Track when a showroom starts a free trial
 * This is the PRIMARY conversion event
 */
export const trackTrialSignup = (data: {
  showroomName: string;
  showroomCode: string;
  email: string;
}) => {
  if (!isGtagAvailable()) return;

  window.gtag('event', 'trial_signup', {
    event_category: 'conversion',
    event_label: data.showroomCode,
    showroom_name: data.showroomName,
    email_domain: data.email.split('@')[1],
  });

  // Also track as a GA4 recommended conversion event
  window.gtag('event', 'sign_up', {
    method: 'free_trial',
  });
};

/**
 * Track demo request submissions
 */
export const trackDemoRequest = (data: {
  name: string;
  email: string;
  company?: string;
}) => {
  if (!isGtagAvailable()) return;

  window.gtag('event', 'demo_request', {
    event_category: 'conversion',
    event_label: data.company || 'unknown',
    email_domain: data.email.split('@')[1],
  });

  // Also track as lead generation
  window.gtag('event', 'generate_lead', {
    currency: 'USD',
    value: 100, // Estimated lead value
  });
};

/**
 * Track contact form submissions
 */
export const trackContactFormSubmit = (data: {
  subject?: string;
  email: string;
}) => {
  if (!isGtagAvailable()) return;

  window.gtag('event', 'contact_form_submit', {
    event_category: 'conversion',
    event_label: data.subject || 'general',
    email_domain: data.email.split('@')[1],
  });
};

// ============================================
// ENGAGEMENT EVENTS
// ============================================

/**
 * Track when a customer completes a room scan
 */
export const trackScanCompleted = (data: {
  roomType: string;
  showroomCode: string;
  scanDuration?: number;
}) => {
  if (!isGtagAvailable()) return;

  window.gtag('event', 'scan_completed', {
    event_category: 'engagement',
    event_label: data.roomType,
    showroom_code: data.showroomCode,
    scan_duration: data.scanDuration,
  });
};

/**
 * Track when a showroom views their submitted scans
 */
export const trackViewScans = (data: {
  showroomCode: string;
  scanCount: number;
}) => {
  if (!isGtagAvailable()) return;

  window.gtag('event', 'view_scans', {
    event_category: 'engagement',
    event_label: data.showroomCode,
    scan_count: data.scanCount,
  });
};

/**
 * Track when a user downloads a floor plan
 */
export const trackFloorPlanDownload = (data: {
  format: 'pdf' | 'dxf' | 'png';
  scanId: string;
}) => {
  if (!isGtagAvailable()) return;

  window.gtag('event', 'floor_plan_download', {
    event_category: 'engagement',
    event_label: data.format,
    scan_id: data.scanId,
  });
};

/**
 * Track when a user exports data
 */
export const trackDataExport = (data: {
  exportType: string;
  itemCount: number;
}) => {
  if (!isGtagAvailable()) return;

  window.gtag('event', 'data_export', {
    event_category: 'engagement',
    event_label: data.exportType,
    item_count: data.itemCount,
  });
};

// ============================================
// FUNNEL TRACKING EVENTS
// ============================================

/**
 * Track when user views pricing page
 */
export const trackViewPricing = () => {
  if (!isGtagAvailable()) return;

  window.gtag('event', 'view_pricing', {
    event_category: 'funnel',
    event_label: 'pricing_page',
  });
};

/**
 * Track when user starts trial signup form
 */
export const trackBeginTrialForm = () => {
  if (!isGtagAvailable()) return;

  window.gtag('event', 'begin_trial_form', {
    event_category: 'funnel',
    event_label: 'trial_form_started',
  });
};

/**
 * Track trial form field completion (for drop-off analysis)
 */
export const trackTrialFormProgress = (field: string) => {
  if (!isGtagAvailable()) return;

  window.gtag('event', 'trial_form_progress', {
    event_category: 'funnel',
    event_label: field,
  });
};

/**
 * Track feature page views for interest analysis
 */
export const trackFeatureView = (featureName: string) => {
  if (!isGtagAvailable()) return;

  window.gtag('event', 'view_feature', {
    event_category: 'interest',
    event_label: featureName,
  });
};

// ============================================
// VIDEO & CONTENT ENGAGEMENT
// ============================================

/**
 * Track video interactions
 */
export const trackVideoEvent = (data: {
  action: 'play' | 'pause' | 'complete' | 'progress';
  videoTitle: string;
  percentWatched?: number;
}) => {
  if (!isGtagAvailable()) return;

  window.gtag('event', `video_${data.action}`, {
    event_category: 'video',
    event_label: data.videoTitle,
    percent_watched: data.percentWatched,
  });
};

// ============================================
// ERROR TRACKING
// ============================================

/**
 * Track errors for debugging and UX improvement
 */
export const trackError = (data: {
  errorType: string;
  errorMessage: string;
  page: string;
}) => {
  if (!isGtagAvailable()) return;

  window.gtag('event', 'error', {
    event_category: 'error',
    event_label: data.errorType,
    error_message: data.errorMessage,
    page_location: data.page,
  });
};

// ============================================
// SEARCH & NAVIGATION
// ============================================

/**
 * Track internal search usage
 */
export const trackSearch = (searchTerm: string, resultsCount: number) => {
  if (!isGtagAvailable()) return;

  window.gtag('event', 'search', {
    search_term: searchTerm,
    results_count: resultsCount,
  });
};

/**
 * Track outbound link clicks
 */
export const trackOutboundLink = (url: string) => {
  if (!isGtagAvailable()) return;

  window.gtag('event', 'click', {
    event_category: 'outbound',
    event_label: url,
    transport_type: 'beacon',
  });
};

// ============================================
// SUBSCRIPTION EVENTS
// ============================================

/**
 * Track subscription plan views
 */
export const trackViewSubscriptionPlans = () => {
  if (!isGtagAvailable()) return;

  window.gtag('event', 'view_subscription_plans', {
    event_category: 'subscription',
  });
};

/**
 * Track subscription upgrade
 */
export const trackSubscriptionUpgrade = (data: {
  fromPlan: string;
  toPlan: string;
  value: number;
}) => {
  if (!isGtagAvailable()) return;

  window.gtag('event', 'purchase', {
    transaction_id: `SUB_${Date.now()}`,
    value: data.value,
    currency: 'USD',
    items: [{
      item_id: data.toPlan,
      item_name: `CabinetScan ${data.toPlan}`,
      item_category: 'subscription',
      price: data.value,
      quantity: 1,
    }],
  });

  window.gtag('event', 'subscription_upgrade', {
    event_category: 'subscription',
    event_label: `${data.fromPlan}_to_${data.toPlan}`,
    value: data.value,
  });
};

/**
 * Track subscription cancellation
 */
export const trackSubscriptionCancel = (data: {
  plan: string;
  reason?: string;
}) => {
  if (!isGtagAvailable()) return;

  window.gtag('event', 'subscription_cancel', {
    event_category: 'subscription',
    event_label: data.plan,
    cancel_reason: data.reason,
  });
};
