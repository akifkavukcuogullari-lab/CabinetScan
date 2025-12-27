'use client'

import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from '@/components/ui/accordion'
import { Webhook, Copy, Check } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { useState } from 'react'

interface WebhookPayloadViewerProps {
  payload: Record<string, unknown>
  defaultOpen?: boolean
}

export function WebhookPayloadViewer({ payload, defaultOpen = false }: WebhookPayloadViewerProps) {
  const [copied, setCopied] = useState(false)
  const jsonString = JSON.stringify(payload, null, 2)

  const copyToClipboard = async () => {
    await navigator.clipboard.writeText(jsonString)
    setCopied(true)
    setTimeout(() => setCopied(false), 2000)
  }

  return (
    <Accordion type="single" collapsible defaultValue={defaultOpen ? 'webhook' : undefined}>
      <AccordionItem value="webhook" className="border rounded-lg">
        <AccordionTrigger className="px-4 py-3 hover:no-underline">
          <div className="flex items-center gap-3">
            <Webhook className="h-5 w-5 text-purple-600" />
            <div className="text-left">
              <div className="font-medium">Webhook Payload</div>
              <div className="text-sm text-gray-500 font-normal">
                JSON data sent to the showroom&apos;s webhook URL
              </div>
            </div>
          </div>
        </AccordionTrigger>
        <AccordionContent className="px-4 pb-4">
          <div className="relative">
            <Button
              variant="outline"
              size="sm"
              className="absolute top-2 right-2 z-10"
              onClick={copyToClipboard}
            >
              {copied ? (
                <>
                  <Check className="h-4 w-4 mr-1" />
                  Copied
                </>
              ) : (
                <>
                  <Copy className="h-4 w-4 mr-1" />
                  Copy
                </>
              )}
            </Button>
            <pre className="bg-gray-50 border rounded-lg p-4 pr-24 overflow-x-auto text-xs font-mono max-h-[400px] overflow-y-auto">
              {jsonString}
            </pre>
          </div>
        </AccordionContent>
      </AccordionItem>
    </Accordion>
  )
}
