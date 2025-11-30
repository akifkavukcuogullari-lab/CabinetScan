/**
 * Comprehensive error handling utilities for Nextlyn Scan Dashboard
 * Transforms technical database/API errors into user-friendly messages
 */

// PostgreSQL error codes mapped to user-friendly messages
const POSTGRES_ERROR_CODES: Record<string, { title: string; message: string; suggestion?: string }> = {
  // Class 23 - Integrity Constraint Violation
  '23000': {
    title: 'Data Conflict',
    message: 'This operation conflicts with existing data.',
    suggestion: 'Please review your inputs and try again.',
  },
  '23001': {
    title: 'Cannot Delete',
    message: 'This item cannot be deleted because it is being used elsewhere.',
    suggestion: 'Remove the related items first, then try again.',
  },
  '23502': {
    title: 'Required Field Missing',
    message: 'A required field is missing.',
    suggestion: 'Please fill in all required fields and try again.',
  },
  '23503': {
    title: 'Related Data Exists',
    message: 'Cannot complete this action because related data exists.',
    suggestion: 'Remove or update the related items first.',
  },
  '23505': {
    title: 'Duplicate Entry',
    message: 'This value already exists.',
    suggestion: 'Please use a different value.',
  },
  '23514': {
    title: 'Invalid Data',
    message: 'The data provided does not meet the required criteria.',
    suggestion: 'Please check your inputs and try again.',
  },

  // Class 42 - Syntax Error or Access Rule Violation
  '42501': {
    title: 'Permission Denied',
    message: 'You do not have permission to perform this action.',
    suggestion: 'Please contact your administrator if you believe this is an error.',
  },
  '42P01': {
    title: 'Resource Not Found',
    message: 'The requested resource could not be found.',
    suggestion: 'Please refresh the page and try again.',
  },

  // Class 53 - Insufficient Resources
  '53000': {
    title: 'Server Busy',
    message: 'The server is currently unable to handle this request.',
    suggestion: 'Please try again in a few moments.',
  },
  '53100': {
    title: 'Storage Limit',
    message: 'Storage limit has been reached.',
    suggestion: 'Please contact support to increase your storage limit.',
  },
  '53200': {
    title: 'Too Many Connections',
    message: 'The server is experiencing high traffic.',
    suggestion: 'Please try again in a few moments.',
  },

  // Class 54 - Program Limit Exceeded
  '54000': {
    title: 'Request Too Large',
    message: 'The request exceeds the maximum allowed size.',
    suggestion: 'Please reduce the size of your request.',
  },

  // Class 57 - Operator Intervention
  '57014': {
    title: 'Request Cancelled',
    message: 'The operation was cancelled due to timeout.',
    suggestion: 'Please try again.',
  },

  // Class 28 - Invalid Authorization Specification
  '28000': {
    title: 'Authentication Failed',
    message: 'Invalid authentication credentials.',
    suggestion: 'Please check your login details and try again.',
  },
  '28P01': {
    title: 'Invalid Password',
    message: 'The password provided is incorrect.',
    suggestion: 'Please check your password and try again.',
  },
}

// HTTP status codes mapped to user-friendly messages
const HTTP_STATUS_MESSAGES: Record<number, { title: string; message: string }> = {
  400: {
    title: 'Invalid Request',
    message: 'The request could not be processed. Please check your inputs.',
  },
  401: {
    title: 'Authentication Required',
    message: 'Please sign in to continue.',
  },
  403: {
    title: 'Access Denied',
    message: 'You do not have permission to access this resource.',
  },
  404: {
    title: 'Not Found',
    message: 'The requested resource could not be found.',
  },
  408: {
    title: 'Request Timeout',
    message: 'The request took too long to complete.',
  },
  409: {
    title: 'Conflict',
    message: 'This operation conflicts with existing data.',
  },
  422: {
    title: 'Validation Error',
    message: 'The provided data is invalid.',
  },
  429: {
    title: 'Too Many Requests',
    message: 'You have made too many requests. Please wait a moment.',
  },
  500: {
    title: 'Server Error',
    message: 'An unexpected error occurred. Please try again later.',
  },
  502: {
    title: 'Service Unavailable',
    message: 'The service is temporarily unavailable. Please try again later.',
  },
  503: {
    title: 'Service Unavailable',
    message: 'The service is temporarily unavailable. Please try again later.',
  },
  504: {
    title: 'Gateway Timeout',
    message: 'The request took too long to complete. Please try again.',
  },
}

// Supabase-specific error messages
const SUPABASE_ERROR_MESSAGES: Record<string, { title: string; message: string }> = {
  'Invalid login credentials': {
    title: 'Login Failed',
    message: 'The email or password you entered is incorrect.',
  },
  'Email not confirmed': {
    title: 'Email Not Verified',
    message: 'Please verify your email address before signing in.',
  },
  'User already registered': {
    title: 'Account Exists',
    message: 'An account with this email already exists.',
  },
  'Password should be at least 6 characters': {
    title: 'Weak Password',
    message: 'Password must be at least 6 characters long.',
  },
  'Invalid email': {
    title: 'Invalid Email',
    message: 'Please enter a valid email address.',
  },
  'Token expired': {
    title: 'Session Expired',
    message: 'Your session has expired. Please sign in again.',
  },
  'JWT expired': {
    title: 'Session Expired',
    message: 'Your session has expired. Please sign in again.',
  },
}

// Error type definitions
export interface FormattedError {
  title: string
  message: string
  suggestion?: string
  code?: string
  isRetryable: boolean
}

export interface SupabaseError {
  code?: string
  message?: string
  details?: string
  hint?: string
  status?: number
}

export interface ApiError {
  status?: number
  statusText?: string
  message?: string
  error?: string
}

/**
 * Checks if an error is a network error
 */
export function isNetworkError(error: unknown): boolean {
  if (error instanceof TypeError) {
    const message = error.message.toLowerCase()
    return (
      message.includes('failed to fetch') ||
      message.includes('network') ||
      message.includes('offline') ||
      message.includes('internet')
    )
  }
  return false
}

/**
 * Checks if an error is a timeout error
 */
export function isTimeoutError(error: unknown): boolean {
  if (error instanceof Error) {
    const message = error.message.toLowerCase()
    return message.includes('timeout') || message.includes('timed out')
  }
  if (typeof error === 'object' && error !== null) {
    const err = error as { code?: string }
    return err.code === '57014'
  }
  return false
}

/**
 * Checks if the error is retryable
 */
export function isRetryableError(error: unknown): boolean {
  // Network errors are retryable
  if (isNetworkError(error)) return true

  // Timeout errors are retryable
  if (isTimeoutError(error)) return true

  // Check HTTP status codes
  if (typeof error === 'object' && error !== null) {
    const err = error as { status?: number; code?: string }

    // Server errors (5xx) are usually retryable
    if (err.status && err.status >= 500) return true

    // Too many requests - retryable after waiting
    if (err.status === 429) return true

    // Database connection errors are retryable
    if (err.code && ['53000', '53200', '57014'].includes(err.code)) return true
  }

  return false
}

/**
 * Extracts the constraint name from a unique violation error
 */
function extractConstraintField(error: SupabaseError): string | null {
  const message = error.message || error.details || ''

  // Common patterns for constraint violations
  const patterns = [
    /Key \((\w+)\)=/i,
    /column "(\w+)"/i,
    /constraint "(\w+)_/i,
    /unique_(\w+)/i,
  ]

  for (const pattern of patterns) {
    const match = message.match(pattern)
    if (match) {
      // Convert snake_case to readable format
      return match[1].replace(/_/g, ' ').toLowerCase()
    }
  }

  return null
}

/**
 * Formats a database error into a user-friendly message
 */
export function formatDatabaseError(error: SupabaseError): FormattedError {
  const code = error.code || ''

  // Handle specific PostgreSQL error codes
  const pgError = POSTGRES_ERROR_CODES[code]
  if (pgError) {
    let message = pgError.message

    // Enhance message for unique constraint violations
    if (code === '23505') {
      const field = extractConstraintField(error)
      if (field) {
        message = `This ${field} already exists.`
      }
    }

    return {
      title: pgError.title,
      message,
      suggestion: pgError.suggestion,
      code,
      isRetryable: isRetryableError(error),
    }
  }

  // Handle Supabase-specific messages
  const supabaseMsg = error.message || ''
  for (const [key, value] of Object.entries(SUPABASE_ERROR_MESSAGES)) {
    if (supabaseMsg.toLowerCase().includes(key.toLowerCase())) {
      return {
        ...value,
        code,
        isRetryable: false,
      }
    }
  }

  // Default fallback
  return {
    title: 'Operation Failed',
    message: 'An unexpected error occurred.',
    suggestion: 'Please try again. If the problem persists, contact support.',
    code,
    isRetryable: isRetryableError(error),
  }
}

/**
 * Formats an API/HTTP error into a user-friendly message
 */
export function formatApiError(error: ApiError): FormattedError {
  // Check HTTP status first
  if (error.status) {
    const httpError = HTTP_STATUS_MESSAGES[error.status]
    if (httpError) {
      return {
        ...httpError,
        code: String(error.status),
        isRetryable: error.status >= 500 || error.status === 429,
      }
    }
  }

  // Default fallback
  return {
    title: 'Request Failed',
    message: error.message || error.error || 'An unexpected error occurred.',
    isRetryable: isRetryableError(error),
  }
}

/**
 * Main error formatting function - handles any error type
 */
export function formatError(error: unknown): FormattedError {
  // Handle null/undefined
  if (!error) {
    return {
      title: 'Unknown Error',
      message: 'An unexpected error occurred.',
      isRetryable: false,
    }
  }

  // Handle network errors
  if (isNetworkError(error)) {
    return {
      title: 'Connection Error',
      message: 'Unable to connect to the server.',
      suggestion: 'Please check your internet connection and try again.',
      isRetryable: true,
    }
  }

  // Handle timeout errors
  if (isTimeoutError(error)) {
    return {
      title: 'Request Timeout',
      message: 'The request took too long to complete.',
      suggestion: 'Please try again.',
      isRetryable: true,
    }
  }

  // Handle Supabase/PostgreSQL errors
  if (typeof error === 'object' && error !== null) {
    const err = error as Record<string, unknown>

    // Check for PostgreSQL error code
    if (err.code && typeof err.code === 'string') {
      return formatDatabaseError(err as SupabaseError)
    }

    // Check for HTTP status
    if (err.status && typeof err.status === 'number') {
      return formatApiError(err as ApiError)
    }
  }

  // Handle standard Error objects
  if (error instanceof Error) {
    return {
      title: 'Error',
      message: error.message,
      isRetryable: false,
    }
  }

  // Handle string errors
  if (typeof error === 'string') {
    return {
      title: 'Error',
      message: error,
      isRetryable: false,
    }
  }

  // Fallback
  return {
    title: 'Unknown Error',
    message: 'An unexpected error occurred.',
    suggestion: 'Please try again. If the problem persists, contact support.',
    isRetryable: false,
  }
}

/**
 * Extracts a simple error message from any error type
 * Use this when you just need the message string
 */
export function getErrorMessage(error: unknown): string {
  const formatted = formatError(error)
  return formatted.suggestion
    ? `${formatted.message} ${formatted.suggestion}`
    : formatted.message
}

/**
 * Logs an error with context for debugging
 * Does not expose sensitive details to users
 */
export function logError(error: unknown, context?: Record<string, unknown>): void {
  const timestamp = new Date().toISOString()
  const formatted = formatError(error)

  console.error(`[${timestamp}] ${formatted.title}:`, {
    message: formatted.message,
    code: formatted.code,
    context,
    originalError: error,
  })
}

/**
 * Type guard to check if error has a specific PostgreSQL code
 */
export function hasErrorCode(error: unknown, code: string): boolean {
  if (typeof error === 'object' && error !== null) {
    const err = error as { code?: string }
    return err.code === code
  }
  return false
}

/**
 * Checks if error is a permission/RLS violation
 */
export function isPermissionError(error: unknown): boolean {
  return hasErrorCode(error, '42501')
}

/**
 * Checks if error is a unique constraint violation
 */
export function isUniqueViolation(error: unknown): boolean {
  return hasErrorCode(error, '23505')
}

/**
 * Checks if error is a foreign key violation
 */
export function isForeignKeyViolation(error: unknown): boolean {
  return hasErrorCode(error, '23503')
}

/**
 * Creates a context-specific error formatter
 * Useful for forms where you want more specific messages
 */
export function createContextualErrorFormatter(
  fieldMappings: Record<string, string>
): (error: unknown) => FormattedError {
  return (error: unknown) => {
    const formatted = formatError(error)

    // If it's a unique violation, try to map the field
    if (isUniqueViolation(error)) {
      const err = error as SupabaseError
      const field = extractConstraintField(err)

      if (field && fieldMappings[field]) {
        return {
          ...formatted,
          message: `This ${fieldMappings[field]} is already in use.`,
          suggestion: 'Please choose a different value.',
        }
      }
    }

    return formatted
  }
}
