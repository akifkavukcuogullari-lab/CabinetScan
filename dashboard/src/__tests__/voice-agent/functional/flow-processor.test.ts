/**
 * Functional tests for post-call flow graph traversal logic.
 *
 * Tests edge following, retry call max attempts checking,
 * and stop node termination.
 */
import { describe, it, expect } from 'vitest'

// --------------------------------------------------------------------------
// Types (from voice-agent/types/index.ts)
// --------------------------------------------------------------------------

type FlowNodeType =
  | 'outcome'
  | 'wait'
  | 'sms'
  | 'retry_call'
  | 'send_link'
  | 'condition'
  | 'stop'

interface FlowNode {
  id: string
  type: FlowNodeType
  data: Record<string, unknown>
  position: { x: number; y: number }
}

interface FlowEdge {
  source: string
  target: string
  sourceHandle?: string
}

interface PostCallFlow {
  nodes: FlowNode[]
  edges: FlowEdge[]
}

// --------------------------------------------------------------------------
// Flow processor logic (mirrors what the flow processor does)
// --------------------------------------------------------------------------

function findNextNode(
  flow: PostCallFlow,
  currentNodeId: string,
  sourceHandle?: string
): FlowNode | null {
  const edge = flow.edges.find(
    (e) =>
      e.source === currentNodeId &&
      (sourceHandle ? e.sourceHandle === sourceHandle : !e.sourceHandle)
  )
  if (!edge) return null
  return flow.nodes.find((n) => n.id === edge.target) || null
}

function findOutgoingEdges(flow: PostCallFlow, nodeId: string): FlowEdge[] {
  return flow.edges.filter((e) => e.source === nodeId)
}

function shouldRetry(
  node: FlowNode,
  currentAttempt: number
): { retry: boolean; maxReached: boolean } {
  if (node.type !== 'retry_call') {
    return { retry: false, maxReached: false }
  }
  const maxAttempts = (node.data.maxAttempts as number) || 1
  if (currentAttempt < maxAttempts) {
    return { retry: true, maxReached: false }
  }
  return { retry: false, maxReached: true }
}

function isTerminalNode(node: FlowNode): boolean {
  return node.type === 'stop'
}

function walkFlow(
  flow: PostCallFlow,
  startNodeId: string,
  attemptNumber: number = 1
): { path: string[]; terminated: boolean; retried: boolean } {
  const path: string[] = []
  let currentNodeId: string | null = startNodeId
  let terminated = false
  let retried = false
  let iterations = 0
  const maxIterations = 50 // guard against infinite loops

  while (currentNodeId && iterations < maxIterations) {
    iterations++
    const node = flow.nodes.find((n) => n.id === currentNodeId)
    if (!node) break

    path.push(node.id)

    if (isTerminalNode(node)) {
      terminated = true
      break
    }

    if (node.type === 'retry_call') {
      const { retry, maxReached } = shouldRetry(node, attemptNumber)
      if (retry) {
        retried = true
        break // flow pauses here for a retry
      }
      if (maxReached) {
        // follow the max_reached handle
        const next = findNextNode(flow, currentNodeId, 'max_reached')
        currentNodeId = next?.id || null
        continue
      }
    }

    // Follow default (no sourceHandle) edge
    const next = findNextNode(flow, currentNodeId)
    currentNodeId = next?.id || null
  }

  return { path, terminated, retried }
}

// --------------------------------------------------------------------------
// Test flows
// --------------------------------------------------------------------------

const SIMPLE_FLOW: PostCallFlow = {
  nodes: [
    { id: 'no_answer', type: 'outcome', data: { outcome: 'no_answer' }, position: { x: 0, y: 0 } },
    { id: 'wait_1', type: 'wait', data: { hours: 24 }, position: { x: 100, y: 0 } },
    { id: 'retry_1', type: 'retry_call', data: { maxAttempts: 3 }, position: { x: 200, y: 0 } },
    { id: 'sms_1', type: 'sms', data: { template: 'Follow up SMS' }, position: { x: 300, y: 0 } },
    { id: 'stop_1', type: 'stop', data: {}, position: { x: 400, y: 0 } },
  ],
  edges: [
    { source: 'no_answer', target: 'wait_1' },
    { source: 'wait_1', target: 'retry_1' },
    { source: 'retry_1', target: 'sms_1', sourceHandle: 'max_reached' },
    { source: 'sms_1', target: 'stop_1' },
  ],
}

const DIRECT_STOP_FLOW: PostCallFlow = {
  nodes: [
    { id: 'not_interested', type: 'outcome', data: { outcome: 'not_interested' }, position: { x: 0, y: 0 } },
    { id: 'stop_1', type: 'stop', data: {}, position: { x: 100, y: 0 } },
  ],
  edges: [{ source: 'not_interested', target: 'stop_1' }],
}

const LINK_FLOW: PostCallFlow = {
  nodes: [
    { id: 'interested', type: 'outcome', data: { outcome: 'interested' }, position: { x: 0, y: 0 } },
    { id: 'send_link_1', type: 'send_link', data: {}, position: { x: 100, y: 0 } },
    { id: 'stop_1', type: 'stop', data: {}, position: { x: 200, y: 0 } },
  ],
  edges: [
    { source: 'interested', target: 'send_link_1' },
    { source: 'send_link_1', target: 'stop_1' },
  ],
}

// --------------------------------------------------------------------------
// Tests
// --------------------------------------------------------------------------

describe('findNextNode()', () => {
  it('finds the next node via default edge', () => {
    const next = findNextNode(SIMPLE_FLOW, 'no_answer')
    expect(next).not.toBeNull()
    expect(next!.id).toBe('wait_1')
  })

  it('finds the next node via sourceHandle', () => {
    const next = findNextNode(SIMPLE_FLOW, 'retry_1', 'max_reached')
    expect(next).not.toBeNull()
    expect(next!.id).toBe('sms_1')
  })

  it('returns null when no outgoing edge exists', () => {
    const next = findNextNode(SIMPLE_FLOW, 'stop_1')
    expect(next).toBeNull()
  })

  it('returns null for non-existent node', () => {
    const next = findNextNode(SIMPLE_FLOW, 'non_existent')
    expect(next).toBeNull()
  })
})

describe('findOutgoingEdges()', () => {
  it('returns all outgoing edges for a node', () => {
    const edges = findOutgoingEdges(SIMPLE_FLOW, 'no_answer')
    expect(edges).toHaveLength(1)
    expect(edges[0].target).toBe('wait_1')
  })

  it('returns empty array for terminal node', () => {
    const edges = findOutgoingEdges(SIMPLE_FLOW, 'stop_1')
    expect(edges).toHaveLength(0)
  })
})

describe('shouldRetry()', () => {
  const retryNode: FlowNode = {
    id: 'retry_1',
    type: 'retry_call',
    data: { maxAttempts: 3 },
    position: { x: 0, y: 0 },
  }

  it('returns retry=true when attempt < maxAttempts', () => {
    expect(shouldRetry(retryNode, 1)).toEqual({ retry: true, maxReached: false })
    expect(shouldRetry(retryNode, 2)).toEqual({ retry: true, maxReached: false })
  })

  it('returns maxReached=true when attempt >= maxAttempts', () => {
    expect(shouldRetry(retryNode, 3)).toEqual({ retry: false, maxReached: true })
    expect(shouldRetry(retryNode, 5)).toEqual({ retry: false, maxReached: true })
  })

  it('returns retry=false for non-retry nodes', () => {
    const waitNode: FlowNode = {
      id: 'wait_1',
      type: 'wait',
      data: { hours: 24 },
      position: { x: 0, y: 0 },
    }
    expect(shouldRetry(waitNode, 1)).toEqual({ retry: false, maxReached: false })
  })

  it('defaults to maxAttempts=1 when not specified', () => {
    const retryNoMax: FlowNode = {
      id: 'retry_1',
      type: 'retry_call',
      data: {},
      position: { x: 0, y: 0 },
    }
    expect(shouldRetry(retryNoMax, 1)).toEqual({ retry: false, maxReached: true })
  })
})

describe('isTerminalNode()', () => {
  it('returns true for stop nodes', () => {
    const stopNode: FlowNode = { id: 's', type: 'stop', data: {}, position: { x: 0, y: 0 } }
    expect(isTerminalNode(stopNode)).toBe(true)
  })

  it('returns false for non-stop nodes', () => {
    const waitNode: FlowNode = { id: 'w', type: 'wait', data: {}, position: { x: 0, y: 0 } }
    expect(isTerminalNode(waitNode)).toBe(false)
  })
})

describe('walkFlow()', () => {
  it('walks no_answer flow and retries when attempt < max', () => {
    const result = walkFlow(SIMPLE_FLOW, 'no_answer', 1)
    expect(result.path).toEqual(['no_answer', 'wait_1', 'retry_1'])
    expect(result.retried).toBe(true)
    expect(result.terminated).toBe(false)
  })

  it('walks no_answer flow through max_reached to SMS and stop', () => {
    const result = walkFlow(SIMPLE_FLOW, 'no_answer', 3)
    expect(result.path).toEqual(['no_answer', 'wait_1', 'retry_1', 'sms_1', 'stop_1'])
    expect(result.terminated).toBe(true)
    expect(result.retried).toBe(false)
  })

  it('walks direct stop flow', () => {
    const result = walkFlow(DIRECT_STOP_FLOW, 'not_interested')
    expect(result.path).toEqual(['not_interested', 'stop_1'])
    expect(result.terminated).toBe(true)
  })

  it('walks send_link flow to stop', () => {
    const result = walkFlow(LINK_FLOW, 'interested')
    expect(result.path).toEqual(['interested', 'send_link_1', 'stop_1'])
    expect(result.terminated).toBe(true)
  })

  it('terminates when no outgoing edge is found', () => {
    const orphanFlow: PostCallFlow = {
      nodes: [
        { id: 'orphan', type: 'outcome', data: {}, position: { x: 0, y: 0 } },
      ],
      edges: [],
    }
    const result = walkFlow(orphanFlow, 'orphan')
    expect(result.path).toEqual(['orphan'])
    expect(result.terminated).toBe(false)
  })
})
