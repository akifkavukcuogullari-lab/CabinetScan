'use client'

import { useState, useEffect } from 'react'
import { createClient } from '@/lib/supabase/client'
import { Badge } from '@/components/ui/badge'
import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from '@/components/ui/accordion'
import { Loader2, MapPin, MessageSquare, Phone, Clock } from 'lucide-react'
import type { VoiceAgentLog, SimplifiedOutcome } from '@/types/voice-agent'
import { OUTCOME_COLORS, OUTCOME_LABELS } from '@/types/voice-agent'

interface VoiceAgentLogCardProps {
  projectId: string
  showroomId: string
}

function formatDuration(seconds: number | null): string {
  if (seconds === null || seconds === undefined) return '--'
  const m = Math.floor(seconds / 60)
  const s = seconds % 60
  return `${m}m ${s}s`
}

function formatDate(dateStr: string | null): string {
  if (!dateStr) return '--'
  return new Date(dateStr).toLocaleString(undefined, {
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  })
}

const SMS_STATUS_COLORS: Record<string, string> = {
  sent: 'bg-green-100 text-green-800',
  delivered: 'bg-green-100 text-green-800',
  failed: 'bg-red-100 text-red-800',
  pending: 'bg-yellow-100 text-yellow-800',
  queued: 'bg-blue-100 text-blue-800',
}

const CALL_STATUS_COLORS: Record<string, string> = {
  completed: 'bg-green-100 text-green-800',
  'in-progress': 'bg-blue-100 text-blue-800',
  ringing: 'bg-yellow-100 text-yellow-800',
  queued: 'bg-gray-100 text-gray-800',
  failed: 'bg-red-100 text-red-800',
  busy: 'bg-orange-100 text-orange-800',
  'no-answer': 'bg-yellow-100 text-yellow-800',
  canceled: 'bg-gray-100 text-gray-800',
  pending: 'bg-gray-100 text-gray-800',
}

const FLOW_STATUS_COLORS: Record<string, string> = {
  active: 'bg-blue-100 text-blue-800',
  waiting: 'bg-yellow-100 text-yellow-800',
  completed: 'bg-green-100 text-green-800',
  stopped: 'bg-gray-100 text-gray-800',
}

export function VoiceAgentLogCard({ projectId, showroomId }: VoiceAgentLogCardProps) {
  const supabase = createClient()
  const [logs, setLogs] = useState<VoiceAgentLog[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    async function loadLogs() {
      setLoading(true)
      try {
        const { data, error } = await supabase
          .from('voice_agent_logs')
          .select('*')
          .eq('project_id', projectId)
          .eq('showroom_id', showroomId)
          .order('attempt_number', { ascending: true })

        if (error) throw error
        setLogs(data || [])
      } catch (error) {
        console.error('Error loading voice agent logs:', error)
      } finally {
        setLoading(false)
      }
    }

    loadLogs()
  }, [supabase, projectId, showroomId])

  if (loading) {
    return (
      <div className="flex items-center justify-center py-4">
        <Loader2 className="h-4 w-4 animate-spin text-gray-400" />
      </div>
    )
  }

  if (logs.length === 0) {
    return (
      <p className="text-sm text-gray-400">No voice agent activity for this project.</p>
    )
  }

  return (
    <div className="space-y-3">
      {logs.map((log) => (
        <div
          key={log.id}
          className="rounded-lg border p-4 space-y-3"
        >
          {/* Header row */}
          <div className="flex items-center justify-between flex-wrap gap-2">
            <Badge variant="outline" className="font-mono text-xs">
              Attempt {log.attempt_number}
            </Badge>
            {log.flow_status && (
              <Badge
                className={`text-xs ${FLOW_STATUS_COLORS[log.flow_status] || 'bg-gray-100 text-gray-800'}`}
              >
                Flow: {log.flow_status}
              </Badge>
            )}
          </div>

          {/* Distance info */}
          {(log.distance_miles !== null || log.distance_zone) && (
            <div className="flex items-center gap-2 text-sm text-gray-600">
              <MapPin className="h-4 w-4 text-gray-400" />
              <span>
                {log.distance_miles !== null
                  ? `${log.distance_miles.toFixed(1)} mi`
                  : ''}
                {log.drive_time_minutes !== null
                  ? ` / ${log.drive_time_minutes} min`
                  : ''}
                {log.distance_zone && (
                  <>
                    {' '}
                    &mdash;{' '}
                    <span className="capitalize font-medium">{log.distance_zone}</span>
                  </>
                )}
                {log.customer_type_used && (
                  <>
                    {' / '}
                    <span className="capitalize">{log.customer_type_used}</span>
                  </>
                )}
              </span>
            </div>
          )}

          {/* SMS status */}
          <div className="flex items-center gap-2 text-sm">
            <MessageSquare className="h-4 w-4 text-gray-400" />
            <Badge
              className={`text-xs ${SMS_STATUS_COLORS[log.sms_status] || 'bg-gray-100 text-gray-800'}`}
            >
              SMS: {log.sms_status}
            </Badge>
            {log.sms_sent_at && (
              <span className="text-gray-500 text-xs">
                {formatDate(log.sms_sent_at)}
              </span>
            )}
          </div>

          {/* Call status */}
          <div className="flex items-center gap-2 text-sm">
            <Phone className="h-4 w-4 text-gray-400" />
            <Badge
              className={`text-xs ${CALL_STATUS_COLORS[log.call_status] || 'bg-gray-100 text-gray-800'}`}
            >
              Call: {log.call_status}
            </Badge>
            {log.call_duration_seconds !== null && (
              <span className="flex items-center gap-1 text-gray-500 text-xs">
                <Clock className="h-3 w-3" />
                {formatDuration(log.call_duration_seconds)}
              </span>
            )}
          </div>

          {/* Outcome */}
          {log.outcome && (
            <div className="flex items-center gap-2">
              <Badge
                className={`text-xs ${OUTCOME_COLORS[log.outcome as SimplifiedOutcome] || 'bg-gray-100 text-gray-800'}`}
              >
                {OUTCOME_LABELS[log.outcome as SimplifiedOutcome] || log.outcome}
              </Badge>
            </div>
          )}

          {/* Expandable sections */}
          <Accordion type="single" collapsible>
            {log.call_transcript && (
              <AccordionItem value="transcript">
                <AccordionTrigger className="text-xs text-gray-500 hover:no-underline py-2">
                  Transcript
                </AccordionTrigger>
                <AccordionContent>
                  <pre className="text-xs text-gray-600 whitespace-pre-wrap bg-gray-50 p-3 rounded max-h-60 overflow-y-auto">
                    {log.call_transcript}
                  </pre>
                </AccordionContent>
              </AccordionItem>
            )}
            {log.call_summary && (
              <AccordionItem value="summary">
                <AccordionTrigger className="text-xs text-gray-500 hover:no-underline py-2">
                  Summary
                </AccordionTrigger>
                <AccordionContent>
                  <p className="text-sm text-gray-600">{log.call_summary}</p>
                </AccordionContent>
              </AccordionItem>
            )}
          </Accordion>
        </div>
      ))}
    </div>
  )
}
