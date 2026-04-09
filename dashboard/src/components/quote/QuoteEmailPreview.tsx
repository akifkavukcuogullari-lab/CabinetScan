'use client'

import { useState, useRef, useEffect } from 'react'
import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from '@/components/ui/accordion'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Badge } from '@/components/ui/badge'
import { RichTextEditor } from '@/components/ui/rich-text-editor'
import {
  Mail,
  Send,
  Edit2,
  Check,
  X,
  DollarSign,
  Loader2,
} from 'lucide-react'

// Component to render HTML email in an iframe (preserves all styles)
function EmailHtmlPreview({ html }: { html: string }) {
  const iframeRef = useRef<HTMLIFrameElement>(null)
  const [iframeHeight, setIframeHeight] = useState(400)

  useEffect(() => {
    const iframe = iframeRef.current
    if (!iframe) return

    // Write the HTML content to the iframe
    const doc = iframe.contentDocument || iframe.contentWindow?.document
    if (doc) {
      doc.open()
      doc.write(`
        <!DOCTYPE html>
        <html>
          <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <style>
              body {
                margin: 0;
                padding: 16px;
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
              }
            </style>
          </head>
          <body>${html}</body>
        </html>
      `)
      doc.close()

      // Adjust iframe height to content
      const resizeObserver = new ResizeObserver(() => {
        const body = doc.body
        const docEl = doc.documentElement
        if (body && docEl) {
          const height = Math.max(
            body.scrollHeight,
            body.offsetHeight,
            docEl.clientHeight,
            docEl.scrollHeight,
            docEl.offsetHeight
          )
          setIframeHeight(Math.min(Math.max(height + 32, 200), 800))
        }
      })

      if (doc.body) {
        resizeObserver.observe(doc.body)
      }

      return () => resizeObserver.disconnect()
    }
  }, [html])

  return (
    <iframe
      ref={iframeRef}
      className="w-full border-0 bg-white rounded"
      style={{ height: iframeHeight }}
      title="Quote Email Preview"
      sandbox="allow-same-origin"
    />
  )
}

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

interface QuoteEmailPreviewProps {
  quoteEmail: QuoteEmail
  onSend: (data: {
    quote_email_id: string
    recipient_email?: string
    subject?: string
    body_html?: string
  }) => Promise<void>
  defaultOpen?: boolean
}

export function QuoteEmailPreview({ quoteEmail, onSend, defaultOpen = false }: QuoteEmailPreviewProps) {
  const [isEditing, setIsEditing] = useState(false)
  const [isSending, setIsSending] = useState(false)
  const [editedEmail, setEditedEmail] = useState({
    recipient_email: quoteEmail.recipient_email,
    subject: quoteEmail.subject,
    body_html: quoteEmail.body_html
  })

  const isSent = quoteEmail.status === 'sent'

  const handleSend = async () => {
    setIsSending(true)
    try {
      const hasChanges =
        editedEmail.recipient_email !== quoteEmail.recipient_email ||
        editedEmail.subject !== quoteEmail.subject ||
        editedEmail.body_html !== quoteEmail.body_html

      await onSend({
        quote_email_id: quoteEmail.id,
        ...(hasChanges ? editedEmail : {})
      })
    } finally {
      setIsSending(false)
    }
  }

  const handleCancelEdit = () => {
    setEditedEmail({
      recipient_email: quoteEmail.recipient_email,
      subject: quoteEmail.subject,
      body_html: quoteEmail.body_html
    })
    setIsEditing(false)
  }

  return (
    <Accordion type="single" collapsible defaultValue={defaultOpen ? 'quote-email' : undefined}>
      <AccordionItem value="quote-email" className="border rounded-lg border-blue-200 bg-blue-50/30">
        <AccordionTrigger className="px-4 py-3 hover:no-underline">
          <div className="flex items-center gap-3 flex-1">
            <Mail className="h-5 w-5 text-blue-600" />
            <div className="text-left flex-1">
              <div className="flex items-center gap-2">
                <span className="font-medium">AI-Generated Quote Email</span>
                <Badge variant={isSent ? 'default' : 'secondary'} className="text-xs">
                  {isSent ? 'Sent' : 'Pending'}
                </Badge>
              </div>
              <div className="text-sm text-gray-500 font-normal">
                Review and send the quote to the customer
              </div>
            </div>
            {quoteEmail.grand_total && (
              <span className="text-lg font-bold text-green-700 mr-2">
                {quoteEmail.grand_total}
              </span>
            )}
          </div>
        </AccordionTrigger>
        <AccordionContent className="px-4 pb-4">
          <div className="space-y-4">
            {/* Edit/Cancel buttons */}
            {!isSent && (
              <div className="flex justify-end gap-2">
                {isEditing ? (
                  <>
                    <Button variant="ghost" size="sm" onClick={handleCancelEdit}>
                      <X className="h-4 w-4 mr-1" />
                      Cancel
                    </Button>
                    <Button variant="outline" size="sm" onClick={() => setIsEditing(false)}>
                      <Check className="h-4 w-4 mr-1" />
                      Done Editing
                    </Button>
                  </>
                ) : (
                  <Button variant="outline" size="sm" onClick={() => setIsEditing(true)}>
                    <Edit2 className="h-4 w-4 mr-1" />
                    Edit
                  </Button>
                )}
              </div>
            )}

            {/* Quote Summary Bar */}
            {quoteEmail.quote_summary && (
              <div className="flex items-center gap-4 p-3 bg-white rounded-lg border">
                <DollarSign className="h-5 w-5 text-green-600" />
                <div className="flex gap-4 text-sm">
                  {quoteEmail.quote_summary.cabinets && (
                    <span>Cabinets: <strong>{quoteEmail.quote_summary.cabinets}</strong></span>
                  )}
                  {quoteEmail.quote_summary.countertops && (
                    <span>Countertops: <strong>{quoteEmail.quote_summary.countertops}</strong></span>
                  )}
                  {quoteEmail.quote_summary.backsplash && (
                    <span>Backsplash: <strong>{quoteEmail.quote_summary.backsplash}</strong></span>
                  )}
                </div>
                <div className="ml-auto text-lg font-bold text-green-700">
                  Total: {quoteEmail.grand_total}
                </div>
              </div>
            )}

            {/* Email Fields */}
            <div className="bg-white rounded-lg border overflow-hidden">
              {/* To Field */}
              <div className="flex items-center border-b px-4 py-2">
                <Label className="w-20 text-sm text-gray-500">To:</Label>
                {isEditing ? (
                  <Input
                    value={editedEmail.recipient_email}
                    onChange={(e) => setEditedEmail({ ...editedEmail, recipient_email: e.target.value })}
                    className="border-0 shadow-none focus-visible:ring-0"
                  />
                ) : (
                  <span className="text-sm">{editedEmail.recipient_email}</span>
                )}
              </div>

              {/* Subject Field */}
              <div className="flex items-center border-b px-4 py-2">
                <Label className="w-20 text-sm text-gray-500">Subject:</Label>
                {isEditing ? (
                  <Input
                    value={editedEmail.subject}
                    onChange={(e) => setEditedEmail({ ...editedEmail, subject: e.target.value })}
                    className="border-0 shadow-none focus-visible:ring-0"
                  />
                ) : (
                  <span className="text-sm font-medium">{editedEmail.subject}</span>
                )}
              </div>

              {/* Email Body - Iframe preview or WYSIWYG Editor */}
              <div className="p-4">
                {isEditing ? (
                  <RichTextEditor
                    content={editedEmail.body_html}
                    onChange={(html) => setEditedEmail({ ...editedEmail, body_html: html })}
                    editable={true}
                    className=""
                  />
                ) : (
                  <EmailHtmlPreview html={editedEmail.body_html} />
                )}
              </div>
            </div>

            {/* Actions */}
            {!isSent && (
              <div className="flex justify-end gap-3 pt-2">
                <Button
                  onClick={handleSend}
                  disabled={isSending}
                  className="bg-blue-600 hover:bg-blue-700"
                >
                  {isSending ? (
                    <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                  ) : (
                    <Send className="h-4 w-4 mr-2" />
                  )}
                  {isSending ? 'Sending...' : 'Send to Customer'}
                </Button>
              </div>
            )}

            {/* Sent info */}
            {isSent && quoteEmail.sent_at && (
              <div className="text-sm text-gray-500 text-right">
                Sent on {new Date(quoteEmail.sent_at).toLocaleString()}
              </div>
            )}
          </div>
        </AccordionContent>
      </AccordionItem>
    </Accordion>
  )
}
