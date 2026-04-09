'use client'

import type { Node } from 'reactflow'
import type { VoiceAgentLog, SimplifiedOutcome } from '@/types/voice-agent'
import { OUTCOME_COLORS, OUTCOME_LABELS } from '@/types/voice-agent'
import { Badge } from '@/components/ui/badge'
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
} from '@/components/ui/card'
import {
  X,
  CheckCircle2,
  XCircle,
  Clock,
  MessageSquare,
  PhoneCall,
  Square,
  GitBranch,
  PhoneOff,
  HelpCircle,
  User,
  Bot,
} from 'lucide-react'
import { format } from 'date-fns'

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function formatTimestamp(ts: string | null | undefined): string {
  if (!ts) return '--'
  try {
    return format(new Date(ts), 'MMM d, yyyy h:mm:ss a')
  } catch {
    return ts
  }
}

function formatDuration(seconds: number | null | undefined): string {
  if (!seconds) return '--'
  const m = Math.floor(seconds / 60)
  const s = seconds % 60
  if (m === 0) return `${s}s`
  return `${m}m ${s}s`
}

function StatusBadge({ status }: { status: 'success' | 'failed' | 'waiting' | 'pending' }) {
  const config = {
    success: {
      label: 'Completed',
      className: 'bg-green-100 text-green-800 border-green-200',
    },
    failed: {
      label: 'Failed',
      className: 'bg-red-100 text-red-800 border-red-200',
    },
    waiting: {
      label: 'Waiting',
      className: 'bg-amber-100 text-amber-800 border-amber-200',
    },
    pending: {
      label: 'Pending',
      className: 'bg-gray-100 text-gray-800 border-gray-200',
    },
  }[status]

  return (
    <Badge variant="outline" className={config.className}>
      {config.label}
    </Badge>
  )
}

// ---------------------------------------------------------------------------
// Transcript Chat View
// ---------------------------------------------------------------------------

interface TranscriptMessage {
  speaker: 'ai' | 'customer'
  text: string
}

function parseTranscript(transcript: string | null | undefined): TranscriptMessage[] {
  if (!transcript) return []

  const messages: TranscriptMessage[] = []
  const lines = transcript.split('\n').filter((l) => l.trim())

  for (const line of lines) {
    const trimmed = line.trim()

    // Try to match speaker prefix patterns: "AI:", "Assistant:", "Bot:", "User:", "Customer:", "Human:"
    const aiMatch = trimmed.match(/^(AI|Assistant|Bot|Agent)\s*:\s*(.*)/i)
    const customerMatch = trimmed.match(
      /^(User|Customer|Human|Caller)\s*:\s*(.*)/i
    )

    if (aiMatch) {
      messages.push({ speaker: 'ai', text: aiMatch[2].trim() })
    } else if (customerMatch) {
      messages.push({ speaker: 'customer', text: customerMatch[2].trim() })
    } else if (messages.length > 0) {
      // Continuation of previous message
      messages[messages.length - 1].text += ' ' + trimmed
    } else {
      // Default to AI if no prefix detected
      messages.push({ speaker: 'ai', text: trimmed })
    }
  }

  return messages
}

function TranscriptChat({ transcript }: { transcript: string | null | undefined }) {
  const messages = parseTranscript(transcript)

  if (messages.length === 0) {
    return (
      <p className="text-xs text-muted-foreground italic">
        No transcript available.
      </p>
    )
  }

  return (
    <div className="flex flex-col gap-2">
      {messages.map((msg, i) => (
        <div
          key={i}
          className={`flex ${msg.speaker === 'customer' ? 'justify-end' : 'justify-start'}`}
        >
          <div
            className={`flex max-w-[85%] gap-2 rounded-lg px-3 py-2 text-xs leading-relaxed ${
              msg.speaker === 'ai'
                ? 'bg-gray-100 text-gray-800'
                : 'bg-blue-100 text-blue-800'
            }`}
          >
            {msg.speaker === 'ai' ? (
              <Bot className="mt-0.5 size-3 shrink-0 opacity-60" />
            ) : (
              <User className="mt-0.5 size-3 shrink-0 opacity-60" />
            )}
            <span>{msg.text}</span>
          </div>
        </div>
      ))}
    </div>
  )
}

// ---------------------------------------------------------------------------
// Node type icons
// ---------------------------------------------------------------------------

function getNodeIcon(type: string | undefined) {
  switch (type) {
    case 'outcome':
      return <PhoneOff className="size-4" />
    case 'wait':
      return <Clock className="size-4" />
    case 'sms':
      return <MessageSquare className="size-4" />
    case 'retryCall':
      return <PhoneCall className="size-4" />
    case 'condition':
      return <GitBranch className="size-4" />
    case 'stop':
      return <Square className="size-4" />
    default:
      return <HelpCircle className="size-4" />
  }
}

function getNodeLabel(node: Node): string {
  switch (node.type) {
    case 'outcome':
      return node.data?.label || 'Outcome'
    case 'wait':
      return `Wait ${node.data?.hours || 0}h`
    case 'sms':
      return 'SMS'
    case 'retryCall':
      return `Retry Call (max ${node.data?.maxAttempts || 0})`
    case 'condition':
      return 'Condition'
    case 'stop':
      return 'Stop'
    default:
      return 'Node'
  }
}

// ---------------------------------------------------------------------------
// Section components for each node type
// ---------------------------------------------------------------------------

function OutcomeDetails({ node, logs }: { node: Node; logs: VoiceAgentLog[] }) {
  const firstLog = logs[0]
  const outcome = firstLog?.outcome as SimplifiedOutcome | undefined

  return (
    <div className="space-y-4">
      {/* Outcome badge */}
      <div className="space-y-2">
        <h4 className="text-xs font-medium uppercase tracking-wider text-muted-foreground">
          Call Outcome
        </h4>
        {outcome ? (
          <Badge
            variant="outline"
            className={OUTCOME_COLORS[outcome] || 'bg-gray-100 text-gray-800'}
          >
            {OUTCOME_LABELS[outcome] || outcome}
          </Badge>
        ) : (
          <span className="text-sm text-muted-foreground">--</span>
        )}
      </div>

      {/* Vapi ended reason */}
      {firstLog?.vapi_ended_reason && (
        <div className="space-y-1">
          <h4 className="text-xs font-medium uppercase tracking-wider text-muted-foreground">
            Ended Reason
          </h4>
          <p className="rounded bg-muted/50 px-2 py-1 font-mono text-xs">
            {firstLog.vapi_ended_reason}
          </p>
        </div>
      )}

      {/* Duration */}
      <div className="space-y-1">
        <h4 className="text-xs font-medium uppercase tracking-wider text-muted-foreground">
          Call Duration
        </h4>
        <p className="text-sm">
          {formatDuration(firstLog?.call_duration_seconds)}
        </p>
      </div>

      {/* Timestamp */}
      <div className="space-y-1">
        <h4 className="text-xs font-medium uppercase tracking-wider text-muted-foreground">
          Timestamp
        </h4>
        <p className="text-sm">
          {formatTimestamp(firstLog?.call_started_at || firstLog?.created_at)}
        </p>
      </div>
    </div>
  )
}

function WaitDetails({ node, logs }: { node: Node; logs: VoiceAgentLog[] }) {
  const hours = node.data?.hours || 0
  const executionStatus = node.data?.executionStatus
  const latestLog = logs[logs.length - 1]

  return (
    <div className="space-y-4">
      {/* Configured wait time */}
      <div className="space-y-1">
        <h4 className="text-xs font-medium uppercase tracking-wider text-muted-foreground">
          Wait Duration
        </h4>
        <p className="text-sm font-medium">
          {hours >= 24 && hours % 24 === 0
            ? `${hours / 24} day${hours / 24 > 1 ? 's' : ''}`
            : `${hours} hour${hours !== 1 ? 's' : ''}`}
        </p>
      </div>

      {/* Status */}
      <div className="space-y-1">
        <h4 className="text-xs font-medium uppercase tracking-wider text-muted-foreground">
          Status
        </h4>
        {executionStatus === 'waiting' && latestLog?.flow_next_at ? (
          <div className="space-y-1">
            <StatusBadge status="waiting" />
            <p className="text-xs text-muted-foreground">
              Waiting until {formatTimestamp(latestLog.flow_next_at)}
            </p>
          </div>
        ) : executionStatus === 'success' ? (
          <StatusBadge status="success" />
        ) : (
          <StatusBadge status={executionStatus || 'pending'} />
        )}
      </div>

      {/* Timestamps */}
      {latestLog && (
        <div className="space-y-1">
          <h4 className="text-xs font-medium uppercase tracking-wider text-muted-foreground">
            Started At
          </h4>
          <p className="text-sm">{formatTimestamp(latestLog.updated_at)}</p>
        </div>
      )}
    </div>
  )
}

function SmsDetails({ node, logs }: { node: Node; logs: VoiceAgentLog[] }) {
  // Find a log with SMS data
  const smsLog = logs.find((l) => l.sms_status && l.sms_status !== 'pending') || logs[0]
  const template = node.data?.template || ''
  const executionStatus = node.data?.executionStatus
  const hasSmsError = !!smsLog?.sms_error

  return (
    <div className="space-y-4">
      {/* Status */}
      <div className="space-y-1">
        <h4 className="text-xs font-medium uppercase tracking-wider text-muted-foreground">
          SMS Status
        </h4>
        <div className="flex items-center gap-2">
          {hasSmsError ? (
            <>
              <XCircle className="size-4 text-red-500" />
              <Badge variant="outline" className="bg-red-100 text-red-800 border-red-200">
                Failed
              </Badge>
            </>
          ) : executionStatus === 'success' ? (
            <>
              <CheckCircle2 className="size-4 text-green-500" />
              <Badge variant="outline" className="bg-green-100 text-green-800 border-green-200">
                Sent
              </Badge>
            </>
          ) : (
            <StatusBadge status={executionStatus || 'pending'} />
          )}
        </div>
      </div>

      {/* SMS Template/Message */}
      <div className="space-y-1">
        <h4 className="text-xs font-medium uppercase tracking-wider text-muted-foreground">
          Message
        </h4>
        <div className="rounded-md border bg-muted/30 p-3">
          <p className="whitespace-pre-wrap text-xs leading-relaxed">
            {template || 'No template configured'}
          </p>
        </div>
      </div>

      {/* Twilio SID */}
      {smsLog?.sms_sid && (
        <div className="space-y-1">
          <h4 className="text-xs font-medium uppercase tracking-wider text-muted-foreground">
            Twilio SID
          </h4>
          <p className="truncate rounded bg-muted/50 px-2 py-1 font-mono text-xs">
            {smsLog.sms_sid}
          </p>
        </div>
      )}

      {/* Sent at */}
      {smsLog?.sms_sent_at && (
        <div className="space-y-1">
          <h4 className="text-xs font-medium uppercase tracking-wider text-muted-foreground">
            Sent At
          </h4>
          <p className="text-sm">{formatTimestamp(smsLog.sms_sent_at)}</p>
        </div>
      )}

      {/* Error */}
      {smsLog?.sms_error && (
        <div className="space-y-1">
          <h4 className="text-xs font-medium uppercase tracking-wider text-muted-foreground">
            Error
          </h4>
          <div className="rounded-md border border-red-200 bg-red-50 p-2">
            <p className="text-xs text-red-700">{smsLog.sms_error}</p>
          </div>
        </div>
      )}
    </div>
  )
}

function RetryCallDetails({ node, logs }: { node: Node; logs: VoiceAgentLog[] }) {
  const maxAttempts = node.data?.maxAttempts || 3
  // Find retry logs (attempt > 1)
  const retryLogs = logs.filter((l) => l.attempt_number > 1)
  const latestRetry = retryLogs[retryLogs.length - 1]
  const totalRetries = retryLogs.length

  return (
    <div className="space-y-4">
      {/* Attempt info */}
      <div className="space-y-1">
        <h4 className="text-xs font-medium uppercase tracking-wider text-muted-foreground">
          Retry Attempts
        </h4>
        <p className="text-sm font-medium">
          {totalRetries > 0
            ? `Attempt ${latestRetry?.attempt_number || 0} of ${maxAttempts}`
            : `0 of ${maxAttempts} retries used`}
        </p>
      </div>

      {/* Per-attempt details */}
      {retryLogs.map((log) => (
        <div
          key={log.id}
          className="space-y-3 rounded-lg border bg-muted/20 p-3"
        >
          <div className="flex items-center justify-between">
            <span className="text-xs font-semibold">
              Attempt {log.attempt_number}
            </span>
            <div className="flex items-center gap-2">
              {log.call_error ? (
                <Badge variant="outline" className="bg-red-100 text-red-800 border-red-200">
                  Failed
                </Badge>
              ) : log.outcome ? (
                <Badge
                  variant="outline"
                  className={
                    OUTCOME_COLORS[log.outcome as SimplifiedOutcome] ||
                    'bg-gray-100 text-gray-800'
                  }
                >
                  {OUTCOME_LABELS[log.outcome as SimplifiedOutcome] || log.outcome}
                </Badge>
              ) : (
                <Badge variant="outline" className="bg-gray-100 text-gray-800">
                  {log.call_status}
                </Badge>
              )}
            </div>
          </div>

          {/* Duration */}
          {log.call_duration_seconds !== null && (
            <div className="text-xs text-muted-foreground">
              Duration: {formatDuration(log.call_duration_seconds)}
            </div>
          )}

          {/* Summary */}
          {log.call_summary && (
            <div className="space-y-1">
              <h5 className="text-xs font-medium text-muted-foreground">
                Summary
              </h5>
              <div className="rounded-md border border-blue-200 bg-blue-50 p-2">
                <p className="text-xs leading-relaxed text-blue-800">
                  {log.call_summary}
                </p>
              </div>
            </div>
          )}

          {/* Transcript */}
          {log.call_transcript && (
            <div className="space-y-1">
              <h5 className="text-xs font-medium text-muted-foreground">
                Transcript
              </h5>
              <div className="max-h-[300px] overflow-y-auto rounded-md border bg-white p-2">
                <TranscriptChat transcript={log.call_transcript} />
              </div>
            </div>
          )}

          {/* Timestamps */}
          <div className="grid grid-cols-2 gap-2 text-xs text-muted-foreground">
            {log.call_scheduled_at && (
              <div>
                <span className="font-medium">Scheduled:</span>
                <br />
                {formatTimestamp(log.call_scheduled_at)}
              </div>
            )}
            {log.call_started_at && (
              <div>
                <span className="font-medium">Started:</span>
                <br />
                {formatTimestamp(log.call_started_at)}
              </div>
            )}
            {log.call_ended_at && (
              <div>
                <span className="font-medium">Ended:</span>
                <br />
                {formatTimestamp(log.call_ended_at)}
              </div>
            )}
          </div>

          {/* Vapi ended reason */}
          {log.vapi_ended_reason && (
            <div className="text-xs text-muted-foreground">
              <span className="font-medium">Ended reason:</span>{' '}
              <code className="rounded bg-muted px-1 py-0.5 text-[11px]">
                {log.vapi_ended_reason}
              </code>
            </div>
          )}

          {/* Error */}
          {log.call_error && (
            <div className="rounded-md border border-red-200 bg-red-50 p-2">
              <p className="text-xs text-red-700">{log.call_error}</p>
            </div>
          )}
        </div>
      ))}

      {retryLogs.length === 0 && (
        <p className="text-xs text-muted-foreground italic">
          No retry calls have been made yet.
        </p>
      )}
    </div>
  )
}

function StopDetails({ node, logs }: { node: Node; logs: VoiceAgentLog[] }) {
  const executionStatus = node.data?.executionStatus
  const latestLog = logs[logs.length - 1]

  return (
    <div className="space-y-4">
      {/* Status */}
      <div className="space-y-1">
        <h4 className="text-xs font-medium uppercase tracking-wider text-muted-foreground">
          Flow Status
        </h4>
        <div className="flex items-center gap-2">
          {executionStatus === 'success' ? (
            <>
              <Square className="size-4 text-red-500" />
              <span className="text-sm font-medium">
                {latestLog?.flow_status === 'stopped'
                  ? 'Flow stopped'
                  : 'Flow completed'}
              </span>
            </>
          ) : (
            <StatusBadge status={executionStatus || 'pending'} />
          )}
        </div>
      </div>

      {/* Timestamp */}
      {latestLog && (
        <div className="space-y-1">
          <h4 className="text-xs font-medium uppercase tracking-wider text-muted-foreground">
            Timestamp
          </h4>
          <p className="text-sm">{formatTimestamp(latestLog.updated_at)}</p>
        </div>
      )}
    </div>
  )
}

function ConditionDetails({ node, logs }: { node: Node; logs: VoiceAgentLog[] }) {
  const condition = node.data?.condition || ''
  const executionStatus = node.data?.executionStatus

  return (
    <div className="space-y-4">
      {/* Condition expression */}
      <div className="space-y-1">
        <h4 className="text-xs font-medium uppercase tracking-wider text-muted-foreground">
          Condition
        </h4>
        <p className="rounded bg-muted/50 px-2 py-1 font-mono text-xs">
          {condition}
        </p>
      </div>

      {/* Status */}
      <div className="space-y-1">
        <h4 className="text-xs font-medium uppercase tracking-wider text-muted-foreground">
          Result
        </h4>
        <StatusBadge status={executionStatus || 'pending'} />
      </div>
    </div>
  )
}

// ---------------------------------------------------------------------------
// Main NodeDetailPanel
// ---------------------------------------------------------------------------

interface NodeDetailPanelProps {
  node: Node
  logs: VoiceAgentLog[]
  onClose: () => void
}

export function NodeDetailPanel({ node, logs, onClose }: NodeDetailPanelProps) {
  const renderContent = () => {
    switch (node.type) {
      case 'outcome':
        return <OutcomeDetails node={node} logs={logs} />
      case 'wait':
        return <WaitDetails node={node} logs={logs} />
      case 'sms':
        return <SmsDetails node={node} logs={logs} />
      case 'retryCall':
        return <RetryCallDetails node={node} logs={logs} />
      case 'stop':
        return <StopDetails node={node} logs={logs} />
      case 'condition':
        return <ConditionDetails node={node} logs={logs} />
      default:
        return (
          <p className="text-sm text-muted-foreground">
            No details available for this node type.
          </p>
        )
    }
  }

  return (
    <div className="flex h-full w-[320px] shrink-0 flex-col border-l bg-background shadow-lg">
      {/* Header */}
      <div className="flex items-center gap-2 border-b px-4 py-3">
        <div className="flex items-center gap-2 text-foreground">
          {getNodeIcon(node.type)}
          <h3 className="text-sm font-semibold">{getNodeLabel(node)}</h3>
        </div>
        <div className="ml-auto">
          <button
            onClick={onClose}
            className="rounded-md p-1 text-muted-foreground hover:bg-muted hover:text-foreground transition-colors"
          >
            <X className="size-4" />
          </button>
        </div>
      </div>

      {/* Execution status */}
      <div className="border-b px-4 py-2">
        <div className="flex items-center gap-2">
          <span className="text-xs text-muted-foreground">Status:</span>
          <StatusBadge status={node.data?.executionStatus || 'pending'} />
        </div>
      </div>

      {/* Scrollable content */}
      <div className="flex-1 overflow-y-auto p-4">{renderContent()}</div>
    </div>
  )
}
