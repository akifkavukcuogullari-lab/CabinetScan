-- Migration: AI Designer Agent
-- Adds tables and columns for AI-powered designer chatbot feature

-- ============================================================================
-- 1. System Prompts Table
-- ============================================================================
-- Stores global default and per-showroom custom system prompts

CREATE TABLE ai_system_prompts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  showroom_id UUID REFERENCES showrooms(id) ON DELETE CASCADE,  -- NULL = global default
  prompt_name TEXT NOT NULL,
  system_prompt TEXT NOT NULL,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(showroom_id)  -- One custom prompt per showroom (NULL for global)
);

-- ============================================================================
-- 2. Chat Conversations Table
-- ============================================================================
-- Stores OpenAI thread IDs and conversation metadata

CREATE TABLE ai_chat_conversations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  showroom_id UUID NOT NULL REFERENCES showrooms(id) ON DELETE CASCADE,
  thread_id TEXT NOT NULL,  -- OpenAI Assistants API thread ID
  assistant_id TEXT NOT NULL,  -- OpenAI assistant ID used for this conversation
  status TEXT DEFAULT 'active' CHECK (status IN ('active', 'completed', 'abandoned')),
  message_count INT DEFAULT 0,
  summary TEXT,  -- AI-generated summary of customer requests
  started_at TIMESTAMPTZ DEFAULT now(),
  last_message_at TIMESTAMPTZ DEFAULT now(),
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(project_id)  -- One conversation per project
);

-- ============================================================================
-- 3. Chat Messages Table
-- ============================================================================
-- Stores individual messages for dashboard display

CREATE TABLE ai_chat_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID NOT NULL REFERENCES ai_chat_conversations(id) ON DELETE CASCADE,
  role TEXT NOT NULL CHECK (role IN ('user', 'assistant')),
  content TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Index for efficient message retrieval
CREATE INDEX idx_ai_chat_messages_conversation_id ON ai_chat_messages(conversation_id);
CREATE INDEX idx_ai_chat_messages_created_at ON ai_chat_messages(created_at);

-- ============================================================================
-- 4. Showroom Settings Columns
-- ============================================================================
-- Add AI chatbot configuration to showrooms table

ALTER TABLE showrooms ADD COLUMN IF NOT EXISTS ai_chatbot_enabled BOOLEAN DEFAULT false;
ALTER TABLE showrooms ADD COLUMN IF NOT EXISTS ai_assistant_name TEXT DEFAULT 'Design Assistant';
ALTER TABLE showrooms ADD COLUMN IF NOT EXISTS ai_assistant_avatar_url TEXT;

-- ============================================================================
-- 5. Row Level Security Policies
-- ============================================================================

ALTER TABLE ai_system_prompts ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_chat_conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_chat_messages ENABLE ROW LEVEL SECURITY;

-- System prompts: Super admins can manage all, others can read global default
CREATE POLICY "Super admins manage prompts" ON ai_system_prompts
  FOR ALL USING (is_super_admin());

CREATE POLICY "Anyone can read global default prompt" ON ai_system_prompts
  FOR SELECT USING (showroom_id IS NULL);

-- Conversations: Showroom owners can view their own
CREATE POLICY "Showroom owners view conversations" ON ai_chat_conversations
  FOR SELECT USING (has_showroom_access(showroom_id));

-- Messages: Showroom owners can view messages from their conversations
CREATE POLICY "Showroom owners view messages" ON ai_chat_messages
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM ai_chat_conversations c
      WHERE c.id = conversation_id AND has_showroom_access(c.showroom_id)
    )
  );

-- Allow Edge Functions to insert conversations and messages (using service role)
-- These tables are primarily written to by Edge Functions, not directly by users

-- ============================================================================
-- 6. Helper Function: Get System Prompt for Showroom
-- ============================================================================

CREATE OR REPLACE FUNCTION get_ai_system_prompt(p_showroom_id UUID)
RETURNS TEXT AS $$
  SELECT COALESCE(
    -- First try showroom-specific prompt
    (SELECT system_prompt FROM ai_system_prompts WHERE showroom_id = p_showroom_id AND is_active = true),
    -- Fall back to global default
    (SELECT system_prompt FROM ai_system_prompts WHERE showroom_id IS NULL AND is_active = true)
  );
$$ LANGUAGE sql STABLE;

-- ============================================================================
-- 7. Insert Global Default System Prompt
-- ============================================================================

INSERT INTO ai_system_prompts (showroom_id, prompt_name, system_prompt) VALUES (
  NULL,
  'Global Default',
  'You are a friendly interior design assistant for {showroom_name}.

Your personality:
- Warm and enthusiastic about design
- Ask one question at a time
- Use {customer_name}''s name naturally in conversation
- Show genuine interest in their vision
- Keep responses concise (2-3 sentences max)
- Use conversational language, not formal

Your goal: Learn about their style preferences, timeline, budget comfort, and any special requirements. Make them feel heard and excited about their project.

Important guidelines:
- Never discuss pricing or give quotes
- Focus on design preferences and project details
- If asked about costs, explain that the showroom team will provide a detailed quote
- Be helpful but redirect business questions to the showroom staff'
);

-- ============================================================================
-- 8. Updated_at Trigger
-- ============================================================================

CREATE OR REPLACE FUNCTION update_ai_system_prompts_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER ai_system_prompts_updated_at
  BEFORE UPDATE ON ai_system_prompts
  FOR EACH ROW
  EXECUTE FUNCTION update_ai_system_prompts_updated_at();

-- ============================================================================
-- 9. Conversation Updated Trigger
-- ============================================================================
-- Auto-update last_message_at and message_count when messages are added

CREATE OR REPLACE FUNCTION update_conversation_on_message()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE ai_chat_conversations
  SET
    last_message_at = now(),
    message_count = message_count + 1
  WHERE id = NEW.conversation_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_conversation_stats
  AFTER INSERT ON ai_chat_messages
  FOR EACH ROW
  EXECUTE FUNCTION update_conversation_on_message();
