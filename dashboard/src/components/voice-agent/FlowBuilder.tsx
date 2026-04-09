'use client'

import {
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
} from 'react'
import ReactFlow, {
  Controls,
  Background,
  BackgroundVariant,
  useNodesState,
  useEdgesState,
  addEdge,
  type Connection,
  type Edge,
  type Node,
  type NodeChange,
  type EdgeChange,
  ReactFlowProvider,
  type ReactFlowInstance,
} from 'reactflow'
import 'reactflow/dist/style.css'

import { OutcomeNode } from './nodes/OutcomeNode'
import { WaitNode } from './nodes/WaitNode'
import { SmsNode } from './nodes/SmsNode'
import { RetryCallNode } from './nodes/RetryCallNode'
import { ConditionNode } from './nodes/ConditionNode'
import { StopNode } from './nodes/StopNode'

import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Textarea } from '@/components/ui/textarea'
import { Label } from '@/components/ui/label'
import {
  RotateCcw,
  Clock,
  MessageSquare,
  PhoneCall,
  PhoneOff,
  GitBranch,
  Square,
  X,
  ChevronDown,
  ChevronRight,
} from 'lucide-react'

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface FlowBuilderProps {
  flow: { nodes: Node[]; edges: Edge[] }
  onChange: (flow: { nodes: Node[]; edges: Edge[] }) => void
  readOnly?: boolean
}

// ---------------------------------------------------------------------------
// Palette items
// ---------------------------------------------------------------------------

const OUTCOME_PALETTE_ITEMS = [
  { type: 'outcome', label: 'No Answer', defaultData: { outcome: 'no_answer', label: 'No Answer' } },
  { type: 'outcome', label: 'Line Busy', defaultData: { outcome: 'line_busy', label: 'Line Busy' } },
  { type: 'outcome', label: 'Voicemail', defaultData: { outcome: 'voicemail', label: 'Voicemail' } },
  { type: 'outcome', label: 'Ghosted', defaultData: { outcome: 'ghosted', label: 'Ghosted' } },
  { type: 'outcome', label: 'Interested', defaultData: { outcome: 'interested', label: 'Interested' } },
  { type: 'outcome', label: 'Not Interested', defaultData: { outcome: 'not_interested', label: 'Not Interested' } },
  { type: 'outcome', label: 'Link Sent', defaultData: { outcome: 'link_sent', label: 'Link Sent' } },
  { type: 'outcome', label: 'Callback Requested', defaultData: { outcome: 'callback_requested', label: 'Callback Requested' } },
  { type: 'outcome', label: 'Hung Up Early', defaultData: { outcome: 'hung_up_early', label: 'Hung Up Early' } },
  { type: 'outcome', label: 'Technical Error', defaultData: { outcome: 'technical_error', label: 'Technical Error' } },
] as const

const ACTION_PALETTE_ITEMS = [
  { type: 'wait', label: 'Wait', icon: Clock, color: 'bg-gray-50 border-gray-300 text-gray-700', defaultData: { hours: 1 } },
  { type: 'sms', label: 'SMS', icon: MessageSquare, color: 'bg-green-50 border-green-300 text-green-900', defaultData: { template: 'Hello {{customer_first_name}}, ...' } },
  { type: 'retryCall', label: 'Retry Call', icon: PhoneCall, color: 'bg-orange-50 border-orange-300 text-orange-900', defaultData: { maxAttempts: 3 } },
  { type: 'condition', label: 'Condition', icon: GitBranch, color: 'bg-yellow-50 border-yellow-300 text-yellow-900', defaultData: { condition: 'attempt_count >= 3' } },
  { type: 'stop', label: 'Stop', icon: Square, color: 'bg-red-50 border-red-300 text-red-900', defaultData: {} },
] as const

// ---------------------------------------------------------------------------
// Node config panel
// ---------------------------------------------------------------------------

function NodeConfigPanel({
  node,
  onUpdate,
  onClose,
}: {
  node: Node
  onUpdate: (id: string, data: Record<string, unknown>) => void
  onClose: () => void
}) {
  const renderFields = () => {
    switch (node.type) {
      case 'wait':
        return (
          <div className="space-y-3">
            <div className="space-y-2">
              <Label>Wait Mode</Label>
              <div className="flex gap-2">
                <button
                  type="button"
                  onClick={() => onUpdate(node.id, { ...node.data, mode: 'hours' })}
                  className={`flex-1 p-2 rounded-md border-2 text-xs transition-colors ${
                    (node.data.mode || 'hours') === 'hours'
                      ? 'border-blue-500 bg-blue-50'
                      : 'border-gray-200 hover:border-gray-300'
                  }`}
                >
                  Fixed Hours
                </button>
                <button
                  type="button"
                  onClick={() => onUpdate(node.id, { ...node.data, mode: 'next_business_day' })}
                  className={`flex-1 p-2 rounded-md border-2 text-xs transition-colors ${
                    node.data.mode === 'next_business_day'
                      ? 'border-blue-500 bg-blue-50'
                      : 'border-gray-200 hover:border-gray-300'
                  }`}
                >
                  Next Business Day
                </button>
              </div>
            </div>

            {(node.data.mode || 'hours') === 'hours' ? (
              <div className="space-y-2">
                <Label htmlFor="wait-hours">Wait duration (hours)</Label>
                <Input
                  id="wait-hours"
                  type="number"
                  min={1}
                  value={node.data.hours}
                  onChange={(e) =>
                    onUpdate(node.id, { ...node.data, hours: Number(e.target.value) || 1 })
                  }
                />
              </div>
            ) : (
              <p className="text-xs text-muted-foreground">
                Wait until 10 AM the next business day (Mon-Sat) in the showroom timezone. Saturday evening waits until Monday.
              </p>
            )}
          </div>
        )
      case 'sms':
        return (
          <div className="space-y-2">
            <Label htmlFor="sms-template">SMS Template</Label>
            <Textarea
              id="sms-template"
              rows={4}
              value={node.data.template}
              onChange={(e) =>
                onUpdate(node.id, { ...node.data, template: e.target.value })
              }
              placeholder="Hello {{name}}, ..."
            />
            <p className="text-xs text-muted-foreground">
              Use {'{{name}}'}, {'{{phone}}'} for variables.
            </p>
          </div>
        )
      case 'retryCall':
        return (
          <div className="space-y-2">
            <Label htmlFor="retry-max">Max Attempts</Label>
            <Input
              id="retry-max"
              type="number"
              min={1}
              max={10}
              value={node.data.maxAttempts}
              onChange={(e) =>
                onUpdate(node.id, {
                  ...node.data,
                  maxAttempts: Number(e.target.value) || 1,
                })
              }
            />
          </div>
        )
      case 'condition':
        return (
          <div className="space-y-2">
            <Label htmlFor="condition-expr">Condition Expression</Label>
            <Input
              id="condition-expr"
              value={node.data.condition}
              onChange={(e) =>
                onUpdate(node.id, { ...node.data, condition: e.target.value })
              }
              placeholder="attempt_count >= 3"
            />
          </div>
        )
      case 'stop':
        return (
          <p className="text-sm text-muted-foreground">
            Terminates this branch of the flow. No configuration needed.
          </p>
        )
      default:
        return null
    }
  }

  return (
    <div className="absolute right-0 top-0 z-10 flex h-full w-64 flex-col border-l bg-background shadow-lg">
      <div className="flex items-center justify-between border-b px-4 py-3">
        <h3 className="text-sm font-semibold">Configure Node</h3>
        <Button variant="ghost" size="icon-sm" onClick={onClose}>
          <X className="size-4" />
        </Button>
      </div>
      <div className="flex-1 overflow-y-auto p-4">{renderFields()}</div>
    </div>
  )
}

// ---------------------------------------------------------------------------
// Inner flow (needs to be inside ReactFlowProvider)
// ---------------------------------------------------------------------------

function FlowBuilderInner({ flow, onChange, readOnly = false }: FlowBuilderProps) {
  const nodeTypes = useMemo(
    () => ({
      outcome: OutcomeNode,
      wait: WaitNode,
      sms: SmsNode,
      retryCall: RetryCallNode,
      condition: ConditionNode,
      stop: StopNode,
    }),
    []
  )

  const [nodes, setNodes, onNodesChange] = useNodesState(flow.nodes)
  const [edges, setEdges, onEdgesChange] = useEdgesState(flow.edges)
  const [selectedNode, setSelectedNode] = useState<Node | null>(null)
  const [outcomesExpanded, setOutcomesExpanded] = useState(false)

  const reactFlowWrapper = useRef<HTMLDivElement>(null)
  const reactFlowInstance = useRef<ReactFlowInstance | null>(null)
  const suppressSync = useRef(false)

  // Sync props -> state when flow prop changes externally
  useEffect(() => {
    suppressSync.current = true
    setNodes(flow.nodes)
    setEdges(flow.edges)
    // Allow sync callback to fire again after a tick
    setTimeout(() => { suppressSync.current = false }, 0)
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [flow])

  // Propagate state -> parent whenever nodes/edges change
  useEffect(() => {
    if (suppressSync.current) return
    onChange({ nodes, edges })
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [nodes, edges])

  // ---- Connections ----
  const onConnect = useCallback(
    (connection: Connection) => {
      setEdges((eds) => addEdge({ ...connection, animated: true }, eds))
    },
    [setEdges]
  )

  // All node types are deletable now (including outcomes — addable from palette)
  const handleNodesChange = useCallback(
    (changes: NodeChange[]) => {
      onNodesChange(changes)
    },
    [onNodesChange]
  )

  // ---- Node click -> config panel ----
  const onNodeClick = useCallback(
    (_: React.MouseEvent, node: Node) => {
      if (readOnly) return
      setSelectedNode(node)
    },
    [readOnly]
  )

  const handleNodeUpdate = useCallback(
    (id: string, data: Record<string, unknown>) => {
      setNodes((nds) =>
        nds.map((n) => (n.id === id ? { ...n, data } : n))
      )
      setSelectedNode((prev) => (prev && prev.id === id ? { ...prev, data } : prev))
    },
    [setNodes]
  )

  // ---- Drag & drop from palette ----
  const onDragOver = useCallback((event: React.DragEvent) => {
    event.preventDefault()
    event.dataTransfer.dropEffect = 'move'
  }, [])

  const onDrop = useCallback(
    (event: React.DragEvent) => {
      event.preventDefault()

      const type = event.dataTransfer.getData('application/reactflow-type')
      const dataStr = event.dataTransfer.getData('application/reactflow-data')
      if (!type || !reactFlowInstance.current) return

      const position = reactFlowInstance.current.screenToFlowPosition({
        x: event.clientX,
        y: event.clientY,
      })

      const newNode: Node = {
        id: `${type}_${Date.now()}`,
        type,
        position,
        data: dataStr ? JSON.parse(dataStr) : {},
      }

      setNodes((nds) => nds.concat(newNode))
    },
    [setNodes]
  )

  const onInit = useCallback((instance: ReactFlowInstance) => {
    reactFlowInstance.current = instance
  }, [])

  // ---- Pane click deselects ----
  const onPaneClick = useCallback(() => {
    setSelectedNode(null)
  }, [])

  return (
    <div className="relative flex h-full w-full">
      {/* Palette sidebar */}
      {!readOnly && (
        <div className="flex w-[220px] shrink-0 flex-col gap-2 overflow-y-auto border-r bg-muted/30 p-3">
          {/* Outcomes section — collapsible */}
          <button
            type="button"
            onClick={() => setOutcomesExpanded((v) => !v)}
            className="flex w-full cursor-pointer items-center gap-2 rounded-lg border-2 border-blue-300 bg-blue-50 px-3 py-2 text-sm font-medium text-blue-900 transition-shadow hover:shadow-md"
          >
            {outcomesExpanded ? (
              <ChevronDown className="size-4 shrink-0" />
            ) : (
              <ChevronRight className="size-4 shrink-0" />
            )}
            <PhoneOff className="size-4 shrink-0" />
            Call Outcomes
          </button>
          {outcomesExpanded && (
            <div className="ml-2 flex flex-col gap-1.5">
              {OUTCOME_PALETTE_ITEMS.map((item) => (
                <div
                  key={item.defaultData.outcome}
                  draggable
                  onDragStart={(e) => {
                    e.dataTransfer.setData('application/reactflow-type', item.type)
                    e.dataTransfer.setData(
                      'application/reactflow-data',
                      JSON.stringify(item.defaultData)
                    )
                    e.dataTransfer.effectAllowed = 'move'
                  }}
                  className="flex cursor-grab items-center gap-2 rounded-md border border-blue-200 bg-white px-2.5 py-1.5 text-xs font-medium text-blue-800 transition-shadow hover:shadow-md hover:bg-blue-50 active:cursor-grabbing"
                >
                  {item.label}
                </div>
              ))}
            </div>
          )}

          {/* Actions section */}
          <h4 className="mb-1 mt-3 text-xs font-semibold uppercase tracking-wider text-muted-foreground">
            Actions
          </h4>
          {ACTION_PALETTE_ITEMS.map((item) => {
            const Icon = item.icon
            return (
              <div
                key={item.type}
                draggable
                onDragStart={(e) => {
                  e.dataTransfer.setData('application/reactflow-type', item.type)
                  e.dataTransfer.setData(
                    'application/reactflow-data',
                    JSON.stringify(item.defaultData)
                  )
                  e.dataTransfer.effectAllowed = 'move'
                }}
                className={`flex cursor-grab items-center gap-2 rounded-lg border-2 px-3 py-2 text-sm font-medium transition-shadow hover:shadow-md active:cursor-grabbing ${item.color}`}
              >
                <Icon className="size-4 shrink-0" />
                {item.label}
              </div>
            )
          })}
        </div>
      )}

      {/* Canvas */}
      <div ref={reactFlowWrapper} className="relative flex-1">
        {/* Reset button */}
        {!readOnly && (
          <div className="absolute right-3 top-3 z-10">
            <Button
              variant="outline"
              size="sm"
              onClick={() => onChange(flow)}
              className="gap-1.5"
            >
              <RotateCcw className="size-3.5" />
              Reset to Default
            </Button>
          </div>
        )}

        <ReactFlow
          nodes={nodes}
          edges={edges}
          onNodesChange={readOnly ? undefined : handleNodesChange}
          onEdgesChange={readOnly ? undefined : onEdgesChange}
          onConnect={readOnly ? undefined : onConnect}
          onInit={onInit}
          onDragOver={readOnly ? undefined : onDragOver}
          onDrop={readOnly ? undefined : onDrop}
          onNodeClick={onNodeClick}
          onPaneClick={onPaneClick}
          nodeTypes={nodeTypes}
          nodesDraggable={!readOnly}
          nodesConnectable={!readOnly}
          elementsSelectable={!readOnly}
          fitView
          fitViewOptions={{ padding: 0.2 }}
          deleteKeyCode={readOnly ? null : 'Backspace'}
          className="bg-background"
        >
          <Controls showInteractive={false} />
          <Background variant={BackgroundVariant.Dots} gap={16} size={1} />
        </ReactFlow>

        {/* Config panel */}
        {selectedNode && !readOnly && (
          <NodeConfigPanel
            node={selectedNode}
            onUpdate={handleNodeUpdate}
            onClose={() => setSelectedNode(null)}
          />
        )}
      </div>
    </div>
  )
}

// ---------------------------------------------------------------------------
// Exported wrapper with ReactFlowProvider
// ---------------------------------------------------------------------------

export function FlowBuilder(props: FlowBuilderProps) {
  return (
    <ReactFlowProvider>
      <div className="h-[600px] w-full overflow-hidden rounded-lg border">
        <FlowBuilderInner {...props} />
      </div>
    </ReactFlowProvider>
  )
}
