# AI Voice Agent — Implementation Plan

> **Start point:** Branch `develop`, commit `67cb04d` (all prior work committed)
> **Architecture plan:** See `/.claude/plans/misty-wibbling-shell.md` for full feature spec

---

## Agent Overview

7 agents working in parallel across 3 waves. Each agent works in its own git worktree to avoid conflicts.

```
Wave 1 (Foundation — no dependencies)
├── Agent A: Database & Types
├── Agent B: Shared Libraries
└── Agent C: Flow Builder Component

Wave 2 (Backend — depends on Wave 1)
├── Agent D: Edge Functions (all 4)
└── Agent E: Dashboard Pages (admin + showroom + project detail)

Wave 3 (Integration + Testing — depends on Wave 1 + 2)
├── Agent F: Integration (submit-project mod + subscription gate + nav)
└── Agent G: Tests (unit + functional + integration)
```

---

## Wave 1: Foundation (Parallel — No Dependencies)

### Agent A: Database & Types

**Goal:** Create the migration, TypeScript types for both backend and dashboard.

**Files to create:**

1. **`supabase/migrations/118_voice_agent_core.sql`**

   Create 3 tables with full schema as specified in the architecture plan (Section 9):

   - `platform_settings` — key/value store, seed 9 rows (voice_agent_globally_enabled, vapi_api_key, vapi_phone_number_id, twilio_account_sid, twilio_auth_token, twilio_phone_number, google_maps_api_key, va_default_sms_template, va_default_system_prompt), RLS: `is_super_admin()` only
   - `voice_agent_showroom_settings` — 18 columns (id, showroom_id UNIQUE FK, enabled, trigger_mode with CHECK, delay_minutes, distance_threshold_miles, scheduling_link, 8 prompt override TEXTs, post_call_flow JSONB, created_at, updated_at), RLS: `has_showroom_access()` + `is_super_admin()`
   - `voice_agent_logs` — 28 columns as specified (SMS fields, call fields, outcome fields, distance fields, flow fields, meta fields), indexes on project_id/showroom_id/call_status/(flow_status+flow_next_at), RLS: `has_showroom_access()` + `is_super_admin()`
   - Add `updated_at` auto-update triggers for settings and logs tables
   - Seed `platform_settings` with default SMS template: "Hi {{customer_first_name}}, this is {{showroom_name}}! Thank you for submitting your project (Ref: {{reference_number}}). We'd love to help bring your vision to life. We'll give you a quick call shortly to schedule your showroom visit."
   - Seed `platform_settings` with default system prompt: "You are a friendly scheduling assistant calling on behalf of {{showroom_name}}. {{customer_full_name}} recently submitted a project (Ref: {{reference_number}}) and received an SMS from this number. Your goal is to schedule a showroom visit. Introduce yourself, reference their project, offer scheduling options, keep it under 2 minutes, never discuss pricing. If interested, use the send_scheduling_link tool to text them a booking link."
   - Reference existing RLS helpers: `is_super_admin()` and `has_showroom_access(uuid)` already exist in the codebase

2. **`voice-agent/types/index.ts`**

   TypeScript types used by Edge Functions (Deno):
   - `PlatformSetting` — { key, value, description, is_secret, updated_at }
   - `VoiceAgentShowroomSettings` — all 18 columns typed
   - `VoiceAgentLog` — all 28 columns typed
   - `VoiceAgentTriggerPayload` — the webhook contract (project_id, showroom_id, customer, end_client, project, showroom, triggered_by)
   - `TemplateVariables` — all 30+ variable keys
   - `SimplifiedOutcome` — union type of 10 outcomes
   - `FlowNodeType` — 'outcome' | 'wait' | 'sms' | 'retry_call' | 'send_link' | 'condition' | 'stop'
   - `FlowNode` — { id, type, data, position }
   - `FlowEdge` — { id?, source, target, sourceHandle? }
   - `PostCallFlow` — { nodes: FlowNode[], edges: FlowEdge[] }
   - `DistanceResult` — { distanceMiles, distanceKm, driveTimeMinutes, zone }

3. **`dashboard/src/types/voice-agent.ts`**

   Dashboard-side types (mirrors backend types but with camelCase for React):
   - Same types as above but formatted for dashboard use
   - Add `VoiceAgentLogWithProject` — joined type for display
   - Add `PlatformSettingsMap` — Record<string, string> for easy access

**Verification:** Run `supabase db reset` — all 3 tables exist. TypeScript compiles without errors.

---

### Agent B: Shared Libraries

**Goal:** Create all utility libraries the Edge Functions will import.

**Files to create:**

1. **`voice-agent/lib/twilio.ts`**

   Follow the exact pattern of `/supabase/functions/_shared/email.ts` (read this file first):
   ```
   sendSms({ to: string, body: string, from?: string }): Promise<{ success: boolean, sid?: string, error?: string }>
   ```
   - Read `twilio_account_sid`, `twilio_auth_token`, `twilio_phone_number` from `platform_settings` table using supabaseAdmin client
   - POST to `https://api.twilio.com/2010-04-01/Accounts/{sid}/Messages.json`
   - Basic auth: `${accountSid}:${authToken}` base64 encoded
   - Body: `To={to}&From={from}&Body={body}` (URL-encoded form data)
   - Return Twilio message SID on success

2. **`voice-agent/lib/vapi.ts`**

   ```
   initiateVapiCall({ customerPhone, systemPrompt, firstMessage?, tools?, scheduledAt? }): Promise<{ success: boolean, callId?: string, error?: string }>
   ```
   - Read `vapi_api_key`, `vapi_phone_number_id` from `platform_settings`
   - POST to `https://api.vapi.ai/call`
   - Auth: `Bearer ${vapiApiKey}`
   - Body: transient assistant config with:
     - `phoneNumberId`: from platform_settings
     - `customer.number`: customerPhone (E.164)
     - `assistant.model`: { provider: "openai", model: "gpt-4o", messages: [{ role: "system", content: systemPrompt }] }
     - `assistant.voice`: { provider: "11labs", voiceId: configurable or default }
     - `assistant.firstMessage`: firstMessage or "Hi, this is the scheduling assistant from {{showroom_name}}"
     - `assistant.tools`: tools array (pass through — includes send_scheduling_link)
     - `schedulePlan.earliestAt`: scheduledAt (ISO datetime) if provided
   - Return Vapi call ID on success

3. **`voice-agent/lib/distance.ts`**

   ```
   calculateDistance({ customerAddress, showroomAddress }): Promise<{ distanceMiles: number, distanceKm: number, driveTimeMinutes: number } | null>
   ```
   - Read `google_maps_api_key` from `platform_settings`
   - GET `https://maps.googleapis.com/maps/api/distancematrix/json?origins={customerAddress}&destinations={showroomAddress}&units=imperial&key={key}`
   - Parse response: `rows[0].elements[0].distance.value` (meters → miles), `rows[0].elements[0].duration.value` (seconds → minutes)
   - Return null if address missing, API fails, or status !== 'OK'

4. **`voice-agent/lib/template.ts`**

   ```
   interpolate(template: string, vars: Record<string, string | number | null>): string
   buildTemplateVariables(payload: VoiceAgentTriggerPayload, distance?: DistanceResult): Record<string, string>
   ```
   - `interpolate`: Replace all `{{variable_name}}` tokens. Unknown/null vars → empty string.
   - `buildTemplateVariables`: Map the webhook payload + distance result to all 30+ variable keys:
     - customer_first_name, customer_last_name, customer_full_name (first + " " + last), customer_phone, customer_email, customer_type, customer_address, customer_city, customer_state, customer_zip
     - end_client_first_name, end_client_last_name, end_client_phone, end_client_email, end_client_address
     - project_name, reference_number, project_notes, project_status, submitted_at (formatted as readable date)
     - showroom_name, showroom_phone, showroom_email, showroom_address (full formatted), showroom_city, showroom_state, showroom_code
     - distance_miles, distance_km, drive_time, distance_zone

5. **`voice-agent/lib/constants.ts`**

   - `DEFAULT_SMS_TEMPLATE`: The default SMS text (same as seeded in platform_settings)
   - `DEFAULT_SYSTEM_PROMPT`: The default voice prompt (same as seeded)
   - `DEFAULT_POST_CALL_FLOW`: The complete default flow JSON with all 10 outcome nodes + their default action chains as specified in Section 6b of the architecture plan
   - `VAPI_OUTCOME_MAP`: Record mapping raw Vapi endedReason strings → SimplifiedOutcome (see Section 6a)
   - `SIMPLIFIED_OUTCOMES`: Array of all 10 outcome names for validation

**Verification:** All functions importable from Edge Functions. Types align with Agent A's types.

**Important references to read first:**
- `/supabase/functions/_shared/email.ts` — pattern for twilio.ts
- `/supabase/functions/submit-project/index.ts` — how supabaseAdmin client is created

---

### Agent C: Flow Builder Component

**Goal:** Build the React Flow visual editor for post-call flow configuration.

**Prerequisites:** Run `npm install reactflow` in `/dashboard` first.

**Files to create:**

1. **`dashboard/src/components/voice-agent/FlowBuilder.tsx`**

   Main component. Props: `{ flow: PostCallFlow, onChange: (flow: PostCallFlow) => void, readOnly?: boolean }`

   Features:
   - React Flow canvas with custom node types
   - Left sidebar: node palette with draggable items (Wait, SMS, Retry Call, Send Link, Condition, Stop)
   - Outcome nodes (blue, 10 of them) pre-placed on the left side, cannot be deleted
   - Drag from palette → drop on canvas to create new action nodes
   - Click node → right panel/popover shows inline config:
     - Wait node: hours/days input
     - SMS node: textarea for message template with {{variable}} hints
     - Retry Call node: maxAttempts number input
     - Send Link node: (no config needed — uses showroom's scheduling_link)
     - Condition node: dropdown (attempt_count >= N, time_of_day, etc.)
     - Stop node: (no config)
   - Connect nodes by dragging edges between handles
   - Retry Call node has TWO output handles: "continue" (bottom) and "max reached" (right)
   - Delete nodes/edges with backspace or delete button
   - "Reset to Default" button — replaces flow with DEFAULT_POST_CALL_FLOW from constants
   - Serializes to/from `PostCallFlow` JSON format

2. **`dashboard/src/components/voice-agent/nodes/OutcomeNode.tsx`** — Blue node, shows outcome name + icon, one output handle
3. **`dashboard/src/components/voice-agent/nodes/WaitNode.tsx`** — Gray node, shows "Wait Xh", configurable
4. **`dashboard/src/components/voice-agent/nodes/SmsNode.tsx`** — Green node, shows SMS preview, editable template
5. **`dashboard/src/components/voice-agent/nodes/RetryCallNode.tsx`** — Orange node, shows "Retry (max X)", TWO output handles
6. **`dashboard/src/components/voice-agent/nodes/SendLinkNode.tsx`** — Purple node, shows "Send Scheduling Link"
7. **`dashboard/src/components/voice-agent/nodes/ConditionNode.tsx`** — Yellow node, configurable condition
8. **`dashboard/src/components/voice-agent/nodes/StopNode.tsx`** — Red node, terminal

   All nodes should use shadcn/ui styling consistent with the existing dashboard. Use the existing Tailwind CSS classes.

**Important references to read first:**
- `/dashboard/src/components/` — existing component patterns, shadcn/ui usage
- `/dashboard/package.json` — existing dependencies
- React Flow docs: https://reactflow.dev/examples/interaction/drag-and-drop

**Verification:** Component renders, nodes are draggable, edges connect, flow serializes to valid JSON, "Reset to Default" works.

---

## Wave 2: Backend + Dashboard (Depends on Wave 1)

### Agent D: Edge Functions

**Goal:** Create all 4 Edge Functions + modify submit-project.

**Prerequisites:** Agent A (types) and Agent B (shared libs) must be complete.

**Files to create:**

1. **`supabase/functions/voice-agent-trigger/index.ts`**

   Main orchestrator. Handles both auto-trigger (from submit-project) and manual trigger (from dashboard button).

   Request: POST with `VoiceAgentTriggerPayload` body. Auth: Bearer service role key.

   Flow:
   1. Parse and validate payload
   2. Create supabaseAdmin client (same pattern as submit-project)
   3. Query `platform_settings` → check `voice_agent_globally_enabled === 'true'`
   4. Query `voice_agent_showroom_settings` by `showroom_id` → check `enabled`
   5. If `trigger_mode === 'manual'` AND `triggered_by === 'system'` → return 200 (skip auto)
   6. Check existing `voice_agent_logs` for this `project_id` with `flow_status NOT IN ('completed', 'stopped')` → prevent duplicates (unless this is a retry from flow processor, identified by triggered_by containing 'flow-processor')
   7. Calculate distance via `distance.ts` (skip if no customer address)
   8. Determine zone: `distanceMiles <= distance_threshold_miles` → 'near' else 'far'
   9. Get customer_type from payload (default: 'homeowner')
   10. Select SMS template: `{zone}_{customerType}_sms_template` from showroom settings → fallback to `va_default_sms_template` from platform_settings
   11. Select system prompt: same fallback chain
   12. Build template variables via `template.ts`
   13. Interpolate SMS template
   14. Create `voice_agent_logs` row with all data (attempt_number = count of existing logs for this project + 1)
   15. Send SMS via `twilio.ts` → update log (sms_status, sms_sid, sms_sent_at or sms_error)
   16. Interpolate system prompt
   17. Build Vapi tools array: include `send_scheduling_link` tool if showroom has `scheduling_link` configured
   18. Calculate scheduledAt:
       - Manual/immediate: now + 30 seconds
       - Delayed: now + delay_minutes
   19. Initiate Vapi call via `vapi.ts` → update log (call_status, vapi_call_id, call_scheduled_at)
   20. Set `flow_status = 'active'`
   21. Return 200 with log ID

   CORS: Allow POST from dashboard origin.

2. **`supabase/functions/voice-agent-webhook/index.ts`**

   Receives Vapi server events (POST). No auth (Vapi doesn't send auth headers — verify via webhook secret if configured).

   Handle these event types from Vapi:
   - `call-started` / `status-update` with status 'in-progress': Update `call_started_at`, `call_status = 'in_progress'`
   - `end-of-call-report`: This is the main one. Contains:
     - `call.id` → match to `vapi_call_id` in logs
     - `endedReason` → store in `vapi_ended_reason`, map to simplified outcome using `VAPI_OUTCOME_MAP`
     - `summary` → store in `call_summary`
     - `transcript` → store in `call_transcript` (concatenate all messages)
     - `call.startedAt`, `call.endedAt` → calculate duration
   - For `interested` / `not_interested` outcomes: analyze transcript or summary for keywords if endedReason is ambiguous (assistant-ended-call, customer-ended-call)
   - After setting outcome: look up showroom's `post_call_flow`, find the matching Outcome node, traverse to the next action node
     - If next is Stop → set `flow_status = 'completed'`
     - If next is Wait → set `flow_status = 'waiting'`, `flow_current_node`, `flow_next_at = now + wait hours`
     - If next is SMS/SendLink → execute immediately, then continue to next node
     - If next is RetryCall → set `flow_status = 'waiting'`, `flow_next_at = now` (immediate pickup by cron)
   - Return 200

3. **`supabase/functions/voice-agent-send-link/index.ts`**

   Vapi tool webhook — called mid-conversation when AI decides to send scheduling link.

   Vapi sends: `{ message: { type: "tool-calls", toolCallList: [{ id, name, arguments }] } }`
   Also includes call metadata with `call.id`.

   Flow:
   1. Extract `toolCallId` from request
   2. Look up `voice_agent_logs` by `vapi_call_id` (from call metadata in request)
   3. Get showroom's `scheduling_link` from `voice_agent_showroom_settings`
   4. Send SMS via Twilio: "Here's your link to schedule a visit at {{showroom_name}}: {scheduling_link}"
   5. Update log: set outcome hint (will be finalized by webhook)
   6. Return: `{ results: [{ toolCallId, result: "Scheduling link sent successfully via SMS" }] }`

4. **`supabase/functions/voice-agent-flow-processor/index.ts`**

   Cron processor. Called every 15 minutes via pg_cron or Supabase scheduled function.

   Flow:
   1. Query `voice_agent_logs` where `flow_status = 'waiting'` AND `flow_next_at <= now()` ORDER BY `flow_next_at` LIMIT 50
   2. For each log entry:
      a. Load showroom's `post_call_flow` JSON
      b. Find `flow_current_node` in the flow
      c. Follow the edge to the next node
      d. Execute based on node type:
         - **Wait**: Should already have waited (that's why we're here). Move to next node.
         - **SMS**: Interpolate template from node data, send via Twilio, update log, move to next node.
         - **Retry Call**: Check attempt count. If < maxAttempts → invoke voice-agent-trigger with `triggered_by: 'flow-processor'`. If >= maxAttempts → follow "max reached" output edge.
         - **Send Link**: Send scheduling link SMS, move to next node.
         - **Stop**: Set `flow_status = 'completed'`.
         - **Condition**: Evaluate condition, follow appropriate edge.
      e. If next node is Wait → set `flow_status = 'waiting'`, `flow_next_at = now + wait hours`, `flow_current_node = next node id`
      f. If no next node → set `flow_status = 'completed'`
   3. Log processing stats

   **pg_cron setup** (add to migration):
   ```sql
   SELECT cron.schedule(
     'voice-agent-flow-processor',
     '*/15 * * * *',
     $$SELECT net.http_post(
       url := current_setting('app.settings.supabase_url') || '/functions/v1/voice-agent-flow-processor',
       headers := jsonb_build_object('Authorization', 'Bearer ' || current_setting('app.settings.service_role_key')),
       body := '{}'::jsonb
     )$$
   );
   ```

5. **Modify `supabase/functions/submit-project/index.ts`**

   Add ~20 lines near the end, after the email notification block (~line 1008). Follow the exact same async fire-and-forget pattern:

   ```typescript
   // Voice Agent trigger (async, non-blocking)
   try {
     const { data: vaGlobal } = await supabaseAdmin
       .from('platform_settings')
       .select('value')
       .eq('key', 'voice_agent_globally_enabled')
       .single()

     if (vaGlobal?.value === 'true') {
       const { data: vaSettings } = await supabaseAdmin
         .from('voice_agent_showroom_settings')
         .select('enabled, trigger_mode')
         .eq('showroom_id', submission.showroom_id)
         .single()

       if (vaSettings?.enabled && vaSettings.trigger_mode !== 'manual') {
         // Build full address string for showroom
         const showroomAddress = [showroom.address_line1, showroom.city, showroom.state, showroom.postal_code].filter(Boolean).join(', ')

         fetch(`${Deno.env.get('SUPABASE_URL')}/functions/v1/voice-agent-trigger`, {
           method: 'POST',
           headers: {
             'Authorization': `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}`,
             'Content-Type': 'application/json',
           },
           body: JSON.stringify({
             project_id: project.id,
             showroom_id: submission.showroom_id,
             customer: {
               id: customerId,
               first_name: submission.customer.first_name,
               last_name: submission.customer.last_name,
               phone_normalized: normalizedPhone,
               email: submission.customer.email,
               customer_type: submission.customer.customer_type || 'homeowner',
               address_line1: submission.customer.address_line1 || null,
               city: submission.customer.city || null,
               state: submission.customer.state || null,
               zip_code: submission.customer.zip_code || null,
             },
             end_client: submission.end_client || { first_name: null, last_name: null, phone: null, email: null, address: null },
             project: {
               name: submission.project.name,
               reference_number: refNumber,
               notes: submission.project.notes || null,
               status: 'submitted',
               submitted_at: new Date().toISOString(),
             },
             showroom: {
               name: showroom.name,
               phone: showroom.phone || null,
               email: showroom.email,
               address_line1: showroom.address_line1 || null,
               city: showroom.city || null,
               state: showroom.state || null,
               postal_code: showroom.postal_code || null,
               showroom_code: showroom.showroom_code,
             },
             triggered_by: 'system',
           }),
         }).catch(err => console.error('[VOICE_AGENT] Trigger error:', err))
       }
     }
   } catch (err) {
     console.error('[VOICE_AGENT] Settings check error:', err)
   }
   ```

   **Read submit-project/index.ts first** to understand variable names and the existing async pattern.

**Important references to read first:**
- `/supabase/functions/submit-project/index.ts` — full file, understand structure and variable names
- `/supabase/functions/_shared/email.ts` — pattern reference
- `/voice-agent/types/index.ts` — types from Agent A
- `/voice-agent/lib/*.ts` — shared libs from Agent B
- Vapi docs: https://docs.vapi.ai/calls/outbound-calling, https://docs.vapi.ai/calls/call-ended-reason, https://docs.vapi.ai/server-url/events

**Verification:** Each function deploys without errors. Manual curl to voice-agent-trigger returns 200.

---

### Agent E: Dashboard Pages

**Goal:** Create admin settings page, showroom settings page (3 tabs), log card, trigger button, and project detail integration.

**Prerequisites:** Agent A (types) and Agent C (FlowBuilder) must be complete.

**Files to create:**

1. **`dashboard/src/app/(dashboard)/admin/voice-agent/page.tsx`**

   Super admin configuration page. Follow the pattern of `/dashboard/src/app/(dashboard)/admin/settings/page.tsx`.

   Sections:
   - **Global Toggle**: Switch to enable/disable voice agent globally. Reads/writes `voice_agent_globally_enabled` in `platform_settings`.
   - **API Credentials Card**:
     - Vapi API Key (type="password", masked)
     - Vapi Phone Number ID (text)
     - Twilio Account SID (password, masked)
     - Twilio Auth Token (password, masked)
     - Twilio Phone Number (text, E.164)
     - Google Maps API Key (password, masked)
     - Each with individual Save button
   - **Default Templates Card**:
     - Master default SMS template (textarea, large)
     - Master default system prompt (textarea, extra large)
     - Variable hints: collapsible panel listing all {{variables}}
     - Save button
   - **Webhook URL Card** (read-only):
     - Display: `{SUPABASE_URL}/functions/v1/voice-agent-webhook`
     - Copy button
     - Note: "Configure this URL in your Vapi dashboard → Phone Numbers → Server URL"

   All reads/writes go to `platform_settings` table.

2. **`dashboard/src/app/(dashboard)/showroom/voice-agent/page.tsx`**

   Showroom owner configuration page with 3 tabs. Follow the pattern of `/dashboard/src/app/(dashboard)/showroom/settings/page.tsx`.

   **Visibility**: Check `platform_settings.voice_agent_globally_enabled`. If false, show a message "Voice Agent is not available" or redirect.
   **Feature gate**: Use existing `useSubscription()` hook and `canUseFeature('voiceAgent')`. If not available, show upgrade prompt.

   **Tab 1: General Settings**
   - Enable/disable toggle → `voice_agent_showroom_settings.enabled`
   - Trigger mode radio group: Immediate / Delayed / Manual → `trigger_mode`
   - Delay minutes input (shown when Delayed selected, 1-60) → `delay_minutes`
   - Distance threshold input (miles, number, min 1) → `distance_threshold_miles`
   - Scheduling link input (URL, with helper text "Calendly, Acuity, or any booking URL") → `scheduling_link`
   - Save button

   **Tab 2: Prompts & Templates**
   - 4 sub-tabs or accordion: Near/Homeowner, Near/Contractor, Far/Homeowner, Far/Contractor
   - Each contains:
     - SMS template textarea (label: "SMS Template Override", placeholder: shows master default)
     - System prompt textarea (label: "Voice Agent Prompt Override", placeholder: shows master default)
     - "Reset to Default" button (clears to NULL → will use master default)
   - Variable hints panel (collapsible, lists all {{variables}})
   - Save button

   **Tab 3: Post-Call Flow**
   - Import and render `FlowBuilder` component from Agent C
   - Load `post_call_flow` from `voice_agent_showroom_settings`
   - If null, use `DEFAULT_POST_CALL_FLOW` from constants
   - Save button → writes JSON to `post_call_flow` column
   - "Reset to Default Flow" button

   All reads/writes go to `voice_agent_showroom_settings` table. Create row on first save if doesn't exist (upsert on showroom_id).

3. **`dashboard/src/components/voice-agent/VoiceAgentLogCard.tsx`**

   Card component showing voice agent activity for a project.
   Props: `{ projectId: string, showroomId: string }`

   Fetches `voice_agent_logs` for the project (may be multiple rows for retries).

   Display per attempt:
   - Attempt number badge
   - Distance: "23.5 mi / 35 min — Near / Homeowner" (or "N/A" if no address)
   - SMS: status badge (Sent ✓ / Failed ✗) + timestamp
   - Call: status badge + duration (e.g., "1m 23s")
   - Outcome: colored badge (interested=green, not_interested=red, no_answer=yellow, etc.)
   - Flow status: "Waiting retry in 23h" / "Completed" / "Stopped"
   - Expandable section: call transcript (if available)
   - Expandable section: call summary

   If no logs exist, show nothing (or subtle "No voice agent activity" text).

4. **`dashboard/src/components/voice-agent/TriggerCallButton.tsx`**

   Props: `{ projectId: string, showroomId: string, customerPhone: string, disabled?: boolean }`

   - Button: "Call Customer" with phone icon
   - On click: POST to `/functions/v1/voice-agent-trigger` with full payload (fetch project + customer + showroom data first, or receive as props)
   - Loading state while request is in-flight
   - Success toast: "Voice agent triggered — SMS sent, call scheduled"
   - Error toast: "Failed to trigger voice agent: {error}"
   - Disabled when: no customer phone, or voice agent not enabled for showroom

5. **Modify project detail pages:**

   - `/dashboard/src/app/(dashboard)/showroom/projects/[id]/page.tsx`
   - `/dashboard/src/app/(dashboard)/admin/projects/[id]/page.tsx` (if exists, or designer equivalent)

   Add conditional section:
   ```tsx
   {voiceAgentEnabled && (
     <div>
       <VoiceAgentLogCard projectId={project.id} showroomId={project.showroom_id} />
       <TriggerCallButton projectId={project.id} showroomId={project.showroom_id} customerPhone={project.customer_phone} />
     </div>
   )}
   ```

   Check `platform_settings.voice_agent_globally_enabled` and `voice_agent_showroom_settings.enabled` before rendering.

**Important references to read first:**
- `/dashboard/src/app/(dashboard)/showroom/settings/page.tsx` — main pattern reference (1600+ lines, settings cards, save handlers, feature gating)
- `/dashboard/src/app/(dashboard)/admin/settings/page.tsx` — admin settings pattern
- `/dashboard/src/lib/subscription.ts` — feature gating
- `/dashboard/src/contexts/subscription-context.tsx` — useSubscription hook
- `/dashboard/src/app/(dashboard)/showroom/projects/[id]/page.tsx` — project detail page to modify
- `/dashboard/src/components/` — existing component patterns

**Verification:** Admin page loads, saves credentials. Showroom page loads with 3 tabs. Flow builder renders. Log card shows on project detail.

---

## Wave 3: Integration + Testing

### Agent F: Integration & Wiring

**Goal:** Subscription gate, navigation links, global visibility checks.

**Prerequisites:** All Wave 1 + 2 agents complete.

**Files to modify:**

1. **`dashboard/src/lib/subscription.ts`**

   - Add `voiceAgent: boolean` to `PlanFeatures` interface (after `emailToCustomer`)
   - Set in `planFeatures` record:
     - trial: false
     - starter: false
     - pro: false
     - business: true
     - enterprise: true

2. **Navigation / sidebar** — find the navigation config file and add "Voice Agent" link:
   - For showroom: under the existing nav items, add link to `/showroom/voice-agent` with a Phone icon
   - For admin: add link to `/admin/voice-agent`
   - Both conditionally rendered when `voice_agent_globally_enabled === 'true'`
   - Search for nav/sidebar components in `/dashboard/src/components/` or `/dashboard/src/app/(dashboard)/layout.tsx`

3. **Global visibility hook** — create a small hook or utility:
   ```
   dashboard/src/hooks/useVoiceAgentEnabled.ts
   ```
   Returns `{ globalEnabled: boolean, showroomEnabled: boolean, loading: boolean }`
   Reads from `platform_settings` and `voice_agent_showroom_settings`.
   Used by: nav items, project detail pages, showroom settings page.

**Important references to read first:**
- `/dashboard/src/lib/subscription.ts` — full file
- Dashboard layout/nav files — search for "sidebar", "nav", or route definitions
- `/dashboard/src/contexts/` — existing context patterns

**Verification:** Voice Agent nav item appears/disappears based on global toggle. Feature gate blocks Starter/Pro.

---

### Agent G: Tests

**Goal:** Comprehensive test coverage — unit tests, functional tests, integration tests.

**Files to create:**

All test files in `/voice-agent/tests/` directory.

#### Unit Tests (`voice-agent/tests/unit/`)

1. **`template.test.ts`**
   - `interpolate()` replaces all known variables
   - `interpolate()` handles null/undefined → empty string
   - `interpolate()` leaves unknown {{tokens}} as empty string
   - `interpolate()` handles template with no variables
   - `buildTemplateVariables()` maps all payload fields correctly
   - `buildTemplateVariables()` formats full address
   - `buildTemplateVariables()` formats submitted_at as readable date

2. **`distance.test.ts`** (mock Google Maps API)
   - Returns correct miles/km/minutes for valid addresses
   - Returns null when customer address is missing
   - Returns null when API fails
   - Handles non-OK status from Google Maps
   - Correctly converts meters to miles

3. **`constants.test.ts`**
   - `DEFAULT_POST_CALL_FLOW` is valid JSON
   - Default flow has all 10 outcome nodes
   - All outcome nodes have at least one outgoing edge
   - `VAPI_OUTCOME_MAP` maps all expected Vapi reasons
   - No outcome maps to undefined

4. **`outcome-mapping.test.ts`**
   - Maps `customer-did-not-answer` → `no_answer`
   - Maps `customer-busy` → `line_busy`
   - Maps `voicemail` → `voicemail`
   - Maps `silence-timed-out` → `ghosted`
   - Maps all `error-*` patterns → `technical_error`
   - Maps `customer-ended-call` with duration < 10s → `hung_up_early`
   - Unknown reasons → `technical_error`

#### Functional Tests (`voice-agent/tests/functional/`)

5. **`trigger-flow.test.ts`**
   - Full trigger flow: payload → distance calc → zone determination → template selection → SMS → call
   - Skips auto-trigger when trigger_mode is manual and triggered_by is system
   - Uses near_homeowner prompt for homeowner within threshold
   - Uses far_contractor prompt for contractor beyond threshold
   - Falls back to master default when showroom overrides are NULL
   - Falls back to near zone when no customer address
   - Falls back to homeowner when customer_type not set
   - Prevents duplicate triggers for same project
   - Allows retry triggers from flow processor

6. **`webhook-processing.test.ts`**
   - Processes end-of-call-report → updates all log fields
   - Maps endedReason to correct simplified outcome
   - Stores transcript and summary
   - Calculates call duration correctly
   - Initiates post-call flow after outcome determination
   - Sets flow_status to 'waiting' with correct flow_next_at for Wait nodes
   - Sets flow_status to 'completed' for Stop nodes

7. **`flow-processor.test.ts`**
   - Picks up waiting logs where flow_next_at <= now
   - Executes SMS node → sends SMS → moves to next node
   - Executes Retry Call node → invokes trigger → new log created
   - Retry Call respects maxAttempts → follows max_reached path when exceeded
   - Executes Send Link node → sends scheduling link SMS
   - Handles Stop node → sets flow_status = 'completed'
   - Handles Wait node → sets flow_next_at correctly
   - Ignores logs with flow_next_at in the future
   - Handles missing/invalid flow config gracefully

8. **`send-link-tool.test.ts`**
   - Receives Vapi tool call → sends correct SMS
   - Includes showroom's scheduling_link in message
   - Returns correct toolCallId in response
   - Handles missing scheduling_link gracefully

#### Integration Tests (`voice-agent/tests/integration/`)

9. **`end-to-end.test.ts`**
   - Full flow: trigger → SMS sent → call initiated → webhook received → outcome logged → flow started
   - Manual trigger from dashboard → same flow works
   - Auto-trigger from submit-project webhook → correct behavior based on trigger_mode
   - Distance calculation feeds correct zone into prompt selection
   - Retry loop: no_answer → wait → retry → no_answer → wait → retry → max reached → SMS → stop

10. **`database.test.ts`**
    - platform_settings: CRUD operations, RLS blocks non-super-admin
    - voice_agent_showroom_settings: CRUD, RLS allows showroom owner, blocks others
    - voice_agent_logs: insert, update, RLS scoped to showroom
    - Indexes exist and are used in query plans
    - post_call_flow JSONB stores and retrieves correctly

11. **`feature-gating.test.ts`**
    - Global toggle off → trigger returns early, dashboard pages hidden
    - Global toggle on, showroom disabled → trigger returns early
    - Global toggle on, showroom enabled → trigger executes
    - Starter/Pro plans → voiceAgent feature returns false
    - Business/Enterprise → voiceAgent feature returns true

#### Dashboard Component Tests (`voice-agent/tests/dashboard/`)

12. **`flow-builder.test.tsx`**
    - Renders default flow with all 10 outcome nodes
    - Can add new nodes via drag
    - Can connect nodes with edges
    - Can delete action nodes (not outcome nodes)
    - Can edit node config (wait hours, SMS template, maxAttempts)
    - Reset to default restores original flow
    - Serializes to valid PostCallFlow JSON
    - Read-only mode prevents editing

13. **`settings-page.test.tsx`**
    - Admin page: loads and saves platform_settings correctly
    - Showroom page: loads and saves voice_agent_showroom_settings
    - Tab navigation works (General, Prompts, Post-Call Flow)
    - Feature gate shows upgrade prompt for non-Business plans
    - Hidden when global toggle is off

14. **`log-card.test.tsx`**
    - Renders SMS status, call status, outcome, distance
    - Shows multiple attempts chronologically
    - Transcript expands/collapses
    - TriggerCallButton shows loading/success/error states

**Test framework:** Use the existing test setup in the project. If none exists, use Vitest for the voice-agent libs and Jest/React Testing Library for dashboard components.

**Verification:** All tests pass. Coverage report shows >80% for voice-agent/lib/ and edge functions.

---

## Dependency Graph

```
Wave 1 (parallel):
  Agent A ─── Database & Types
  Agent B ─── Shared Libraries
  Agent C ─── Flow Builder Component

Wave 2 (parallel, after Wave 1):
  Agent D ─── Edge Functions ──── depends on A (types) + B (libs)
  Agent E ─── Dashboard Pages ─── depends on A (types) + C (FlowBuilder)

Wave 3 (parallel, after Wave 2):
  Agent F ─── Integration ─────── depends on D + E
  Agent G ─── Tests ───────────── depends on ALL (A through F)
```

---

## Shared Contracts (All Agents Must Align On)

1. **Type names**: Use exact names from `voice-agent/types/index.ts` (Agent A defines, all others import)
2. **Import paths**: Edge Functions import from `../../voice-agent/lib/` and `../../voice-agent/types/`
3. **Supabase client**: Edge Functions create supabaseAdmin using `Deno.env.get('SUPABASE_URL')` and `Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')` — same pattern as submit-project
4. **Table names**: `platform_settings`, `voice_agent_showroom_settings`, `voice_agent_logs` — exact
5. **Column names**: Exact as specified in Section 9 of architecture plan
6. **Outcome values**: Exactly 10: `no_answer`, `line_busy`, `voicemail`, `ghosted`, `interested`, `not_interested`, `link_sent`, `callback_requested`, `hung_up_early`, `technical_error`
7. **Flow node types**: `outcome`, `wait`, `sms`, `retry_call`, `send_link`, `condition`, `stop`
8. **Template variable format**: `{{snake_case_name}}`
9. **API endpoints**: All Edge Functions accessible at `{SUPABASE_URL}/functions/v1/{function-name}`
10. **Dashboard routes**: `/admin/voice-agent` and `/showroom/voice-agent`
