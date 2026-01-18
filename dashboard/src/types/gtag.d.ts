/**
 * TypeScript type definitions for Google Analytics gtag.js
 */

interface GtagEventParams {
  event_category?: string;
  event_label?: string;
  value?: number;
  currency?: string;
  transaction_id?: string;
  items?: Array<{
    item_id?: string;
    item_name?: string;
    item_category?: string;
    price?: number;
    quantity?: number;
  }>;
  method?: string;
  search_term?: string;
  page_path?: string;
  page_title?: string;
  page_location?: string;
  transport_type?: string;
  // Custom CabinetScan parameters
  showroom_name?: string;
  showroom_code?: string;
  email_domain?: string;
  scan_duration?: number;
  scan_count?: number;
  scan_id?: string;
  item_count?: number;
  percent_watched?: number;
  error_message?: string;
  cancel_reason?: string;
  results_count?: number;
  [key: string]: unknown;
}

interface GtagConfigParams {
  page_path?: string;
  page_title?: string;
  page_location?: string;
  send_page_view?: boolean;
  [key: string]: unknown;
}

type GtagCommand = 'config' | 'event' | 'js' | 'set';

interface Window {
  gtag: (
    command: GtagCommand,
    targetIdOrEventName: string | Date,
    params?: GtagEventParams | GtagConfigParams
  ) => void;
  dataLayer: Array<unknown>;
}

declare function gtag(
  command: 'config',
  targetId: string,
  config?: GtagConfigParams
): void;

declare function gtag(
  command: 'event',
  eventName: string,
  eventParams?: GtagEventParams
): void;

declare function gtag(command: 'js', date: Date): void;

declare function gtag(
  command: 'set',
  targetId: string,
  config: Record<string, unknown>
): void;
