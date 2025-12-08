'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { QuoteEmailPreview } from './QuoteEmailPreview'
import { createClient } from '@/lib/supabase/client'

interface QuoteSummary {
  cabinets?: string
  countertops?: string
  backsplash?: string
  total: string
}

interface QuoteEmail {
  id: string
  recipient_email: string
  subject: string
  body_html: string
  body_text: string | null
  customer_name: string | null
  reference_number: string | null
  grand_total: string | null
  quote_summary: QuoteSummary | null
  status: string
  sent_at: string | null
  created_at: string
}

interface QuoteEmailSectionProps {
  quoteEmail: QuoteEmail
}

export function QuoteEmailSection({ quoteEmail: initialQuoteEmail }: QuoteEmailSectionProps) {
  const router = useRouter()
  const [quoteEmail, setQuoteEmail] = useState(initialQuoteEmail)
  const supabase = createClient()

  const handleSend = async (data: {
    quote_email_id: string
    recipient_email?: string
    subject?: string
    body_html?: string
  }) => {
    // Call the Edge Function to send the quote
    const response = await fetch(
      `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/send-quote-email`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY}`
        },
        body: JSON.stringify(data)
      }
    )

    if (!response.ok) {
      const error = await response.json()
      throw new Error(error.error || 'Failed to send quote email')
    }

    // Update local state to reflect sent status
    setQuoteEmail({
      ...quoteEmail,
      status: 'sent',
      sent_at: new Date().toISOString(),
      ...(data.recipient_email && { recipient_email: data.recipient_email }),
      ...(data.subject && { subject: data.subject }),
      ...(data.body_html && { body_html: data.body_html })
    })

    // Refresh the page to get updated data
    router.refresh()
  }

  return <QuoteEmailPreview quoteEmail={quoteEmail} onSend={handleSend} />
}
