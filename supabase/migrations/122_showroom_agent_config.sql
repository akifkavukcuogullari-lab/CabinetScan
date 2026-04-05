-- Add per-showroom AI agent configuration columns
ALTER TABLE voice_agent_showroom_settings
  ADD COLUMN IF NOT EXISTS llm_provider TEXT,
  ADD COLUMN IF NOT EXISTS llm_model TEXT,
  ADD COLUMN IF NOT EXISTS voice_provider TEXT,
  ADD COLUMN IF NOT EXISTS voice_id TEXT,
  ADD COLUMN IF NOT EXISTS agent_name TEXT,
  ADD COLUMN IF NOT EXISTS first_message TEXT;

-- NULL = use platform default from platform_settings
-- When set, overrides the platform default for this showroom
COMMENT ON COLUMN voice_agent_showroom_settings.llm_provider IS 'Override LLM provider (openai, anthropic, groq). NULL = platform default';
COMMENT ON COLUMN voice_agent_showroom_settings.llm_model IS 'Override LLM model (gpt-4o, gpt-4o-mini, etc.). NULL = platform default';
COMMENT ON COLUMN voice_agent_showroom_settings.voice_provider IS 'Override voice provider (11labs, openai, etc.). NULL = platform default';
COMMENT ON COLUMN voice_agent_showroom_settings.voice_id IS 'Override voice ID from provider. NULL = platform default';
COMMENT ON COLUMN voice_agent_showroom_settings.agent_name IS 'Name the AI uses to introduce itself. NULL = "scheduling assistant"';
COMMENT ON COLUMN voice_agent_showroom_settings.first_message IS 'Override first message when call connects. NULL = platform default';
