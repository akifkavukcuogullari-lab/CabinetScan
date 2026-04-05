/**
 * Functional tests for the send-link tool response format.
 *
 * The send-link Edge Function returns a Vapi-compatible tool response
 * that includes the toolCallId and a result message.
 */
import { describe, it, expect } from 'vitest'

// --------------------------------------------------------------------------
// Inlined tool response builder (mirrors voice-agent-send-link Edge Function)
// --------------------------------------------------------------------------

interface VapiToolCallPayload {
  message: {
    type: string
    toolCallId: string
    functionCall: {
      name: string
      parameters: Record<string, unknown>
    }
  }
}

interface VapiToolResponse {
  results: Array<{
    toolCallId: string
    result: string
  }>
}

function buildSendLinkResponse(
  payload: VapiToolCallPayload,
  success: boolean,
  message: string
): VapiToolResponse {
  return {
    results: [
      {
        toolCallId: payload.message.toolCallId,
        result: success
          ? `Success: ${message}`
          : `Error: ${message}`,
      },
    ],
  }
}

function validateToolCallPayload(
  body: unknown
): { valid: boolean; payload?: VapiToolCallPayload; error?: string } {
  if (!body || typeof body !== 'object') {
    return { valid: false, error: 'Request body is empty or not an object' }
  }

  const data = body as Record<string, unknown>
  const message = data.message as Record<string, unknown> | undefined

  if (!message?.toolCallId) {
    return { valid: false, error: 'Missing toolCallId in message' }
  }

  if (!message?.functionCall) {
    return { valid: false, error: 'Missing functionCall in message' }
  }

  return { valid: true, payload: data as unknown as VapiToolCallPayload }
}

// --------------------------------------------------------------------------
// Tests
// --------------------------------------------------------------------------

describe('buildSendLinkResponse()', () => {
  const mockPayload: VapiToolCallPayload = {
    message: {
      type: 'tool-call',
      toolCallId: 'tc_abc123',
      functionCall: {
        name: 'send_scheduling_link',
        parameters: {},
      },
    },
  }

  it('returns correct Vapi tool response format', () => {
    const response = buildSendLinkResponse(
      mockPayload,
      true,
      'Scheduling link sent via SMS'
    )
    expect(response).toHaveProperty('results')
    expect(response.results).toHaveLength(1)
    expect(response.results[0]).toHaveProperty('toolCallId')
    expect(response.results[0]).toHaveProperty('result')
  })

  it('includes the correct toolCallId from the payload', () => {
    const response = buildSendLinkResponse(
      mockPayload,
      true,
      'Link sent'
    )
    expect(response.results[0].toolCallId).toBe('tc_abc123')
  })

  it('prefixes success message with "Success:"', () => {
    const response = buildSendLinkResponse(
      mockPayload,
      true,
      'Scheduling link sent via SMS'
    )
    expect(response.results[0].result).toBe(
      'Success: Scheduling link sent via SMS'
    )
  })

  it('prefixes error message with "Error:"', () => {
    const response = buildSendLinkResponse(
      mockPayload,
      false,
      'No scheduling link configured'
    )
    expect(response.results[0].result).toBe(
      'Error: No scheduling link configured'
    )
  })
})

describe('validateToolCallPayload()', () => {
  it('accepts a valid payload', () => {
    const body = {
      message: {
        type: 'tool-call',
        toolCallId: 'tc_abc123',
        functionCall: {
          name: 'send_scheduling_link',
          parameters: {},
        },
      },
    }
    const result = validateToolCallPayload(body)
    expect(result.valid).toBe(true)
    expect(result.payload).toBeDefined()
  })

  it('rejects null body', () => {
    const result = validateToolCallPayload(null)
    expect(result.valid).toBe(false)
    expect(result.error).toContain('empty')
  })

  it('rejects body without message.toolCallId', () => {
    const result = validateToolCallPayload({ message: {} })
    expect(result.valid).toBe(false)
    expect(result.error).toContain('toolCallId')
  })

  it('rejects body without message.functionCall', () => {
    const result = validateToolCallPayload({
      message: { toolCallId: 'tc_1' },
    })
    expect(result.valid).toBe(false)
    expect(result.error).toContain('functionCall')
  })
})
