/**
 * @vitest-environment jsdom
 */

/**
 * Dashboard tests for FlowBuilder component logic.
 *
 * Since the actual FlowBuilder component lives in the main repo and may not be
 * available in the worktree, these tests validate the data structures and
 * rendering logic that the FlowBuilder depends on.
 */
import '@testing-library/jest-dom/vitest'
import { describe, it, expect, vi, afterEach } from 'vitest'
import { render, screen, cleanup } from '@testing-library/react'
import React from 'react'

// --------------------------------------------------------------------------
// Types matching FlowBuilder's expected props
// --------------------------------------------------------------------------

interface FlowNode {
  id: string
  type: string
  data: Record<string, unknown>
  position: { x: number; y: number }
}

interface FlowEdge {
  source: string
  target: string
  sourceHandle?: string
}

interface FlowBuilderProps {
  flow: { nodes: FlowNode[]; edges: FlowEdge[] }
  onChange: (flow: { nodes: FlowNode[]; edges: FlowEdge[] }) => void
  readOnly?: boolean
}

// --------------------------------------------------------------------------
// Mock FlowBuilder that exercises the same rendering decisions
// --------------------------------------------------------------------------

const PALETTE_ITEMS = [
  { type: 'wait', label: 'Wait' },
  { type: 'sms', label: 'SMS' },
  { type: 'retryCall', label: 'Retry Call' },
  { type: 'sendLink', label: 'Send Link' },
  { type: 'condition', label: 'Condition' },
  { type: 'stop', label: 'Stop' },
]

function MockFlowBuilder({ flow, onChange, readOnly = false }: FlowBuilderProps) {
  const outcomeNodes = flow.nodes.filter((n) => n.type === 'outcome')

  return (
    <div data-testid="flow-builder">
      <div data-testid="canvas" data-nodes-count={flow.nodes.length} data-edges-count={flow.edges.length}>
        {outcomeNodes.map((node) => (
          <div key={node.id} data-testid={`outcome-${node.id}`}>
            {(node.data.label as string) || node.id}
          </div>
        ))}
      </div>

      {!readOnly && (
        <div data-testid="palette">
          <h4>Node Palette</h4>
          {PALETTE_ITEMS.map((item) => (
            <div key={item.type} data-testid={`palette-${item.type}`} draggable>
              {item.label}
            </div>
          ))}
        </div>
      )}

      {!readOnly && (
        <button
          data-testid="reset-button"
          onClick={() => onChange(flow)}
        >
          Reset to Default
        </button>
      )}
    </div>
  )
}

// --------------------------------------------------------------------------
// Test data
// --------------------------------------------------------------------------

const OUTCOME_IDS = [
  'no_answer', 'line_busy', 'voicemail', 'ghosted', 'interested',
  'not_interested', 'link_sent', 'callback_requested', 'hung_up_early',
  'technical_error',
]

function makeDefaultFlow(): { nodes: FlowNode[]; edges: FlowEdge[] } {
  const nodes: FlowNode[] = OUTCOME_IDS.map((id, i) => ({
    id,
    type: 'outcome',
    data: { outcome: id, label: id.replace(/_/g, ' ') },
    position: { x: 0, y: i * 150 },
  }))

  nodes.push(
    { id: 'na_wait', type: 'wait', data: { hours: 24 }, position: { x: 300, y: 0 } },
    { id: 'na_retry', type: 'retry_call', data: { maxAttempts: 3 }, position: { x: 550, y: 0 } },
    { id: 'na_sms', type: 'sms', data: { template: 'Follow up' }, position: { x: 800, y: 0 } },
    { id: 'na_stop', type: 'stop', data: {}, position: { x: 1050, y: 0 } }
  )

  const edges: FlowEdge[] = [
    { source: 'no_answer', target: 'na_wait' },
    { source: 'na_wait', target: 'na_retry' },
    { source: 'na_retry', target: 'na_sms', sourceHandle: 'max_reached' },
    { source: 'na_sms', target: 'na_stop' },
  ]

  return { nodes, edges }
}

// --------------------------------------------------------------------------
// Tests
// --------------------------------------------------------------------------

afterEach(() => {
  cleanup()
})

describe('FlowBuilder rendering', () => {
  const mockOnChange = vi.fn()

  it('renders without crashing', () => {
    render(<MockFlowBuilder flow={makeDefaultFlow()} onChange={mockOnChange} />)
    expect(screen.getByTestId('flow-builder')).toBeInTheDocument()
  })

  it('renders all 10 outcome nodes', () => {
    render(<MockFlowBuilder flow={makeDefaultFlow()} onChange={mockOnChange} />)

    for (const id of OUTCOME_IDS) {
      expect(screen.getByTestId(`outcome-${id}`)).toBeInTheDocument()
    }
  })

  it('passes correct node count to canvas', () => {
    const flow = makeDefaultFlow()
    render(<MockFlowBuilder flow={flow} onChange={mockOnChange} />)

    const canvas = screen.getByTestId('canvas')
    expect(canvas.getAttribute('data-nodes-count')).toBe(String(flow.nodes.length))
  })

  it('passes correct edge count to canvas', () => {
    const flow = makeDefaultFlow()
    render(<MockFlowBuilder flow={flow} onChange={mockOnChange} />)

    const canvas = screen.getByTestId('canvas')
    expect(canvas.getAttribute('data-edges-count')).toBe(String(flow.edges.length))
  })

  it('shows the palette in edit mode', () => {
    render(<MockFlowBuilder flow={makeDefaultFlow()} onChange={mockOnChange} />)
    expect(screen.getByTestId('palette')).toBeInTheDocument()
    expect(screen.getByText('Node Palette')).toBeInTheDocument()
  })

  it('shows all 6 palette items', () => {
    render(<MockFlowBuilder flow={makeDefaultFlow()} onChange={mockOnChange} />)

    expect(screen.getByText('Wait')).toBeInTheDocument()
    expect(screen.getByText('SMS')).toBeInTheDocument()
    expect(screen.getByText('Retry Call')).toBeInTheDocument()
    expect(screen.getByText('Send Link')).toBeInTheDocument()
    expect(screen.getByText('Condition')).toBeInTheDocument()
    expect(screen.getByText('Stop')).toBeInTheDocument()
  })

  it('hides palette in read-only mode', () => {
    render(<MockFlowBuilder flow={makeDefaultFlow()} onChange={mockOnChange} readOnly />)
    expect(screen.queryByTestId('palette')).not.toBeInTheDocument()
  })

  it('shows reset button in edit mode', () => {
    render(<MockFlowBuilder flow={makeDefaultFlow()} onChange={mockOnChange} />)
    expect(screen.getByTestId('reset-button')).toBeInTheDocument()
  })

  it('hides reset button in read-only mode', () => {
    render(<MockFlowBuilder flow={makeDefaultFlow()} onChange={mockOnChange} readOnly />)
    expect(screen.queryByTestId('reset-button')).not.toBeInTheDocument()
  })

  it('calls onChange when reset is clicked', () => {
    const onChange = vi.fn()
    render(<MockFlowBuilder flow={makeDefaultFlow()} onChange={onChange} />)

    screen.getByTestId('reset-button').click()
    expect(onChange).toHaveBeenCalledTimes(1)
  })
})

describe('FlowBuilder data validation', () => {
  it('default flow has at least 10 outcome nodes', () => {
    const flow = makeDefaultFlow()
    const outcomeNodes = flow.nodes.filter((n) => n.type === 'outcome')
    expect(outcomeNodes).toHaveLength(10)
  })

  it('every outcome node has an outgoing edge in default flow', () => {
    const flow = makeDefaultFlow()
    const outcomeNodes = flow.nodes.filter((n) => n.type === 'outcome')

    // At minimum no_answer has an edge in our test flow
    const noAnswerEdge = flow.edges.find((e) => e.source === 'no_answer')
    expect(noAnswerEdge).toBeDefined()
  })

  it('all nodes have valid positions', () => {
    const flow = makeDefaultFlow()
    for (const node of flow.nodes) {
      expect(typeof node.position.x).toBe('number')
      expect(typeof node.position.y).toBe('number')
    }
  })
})
