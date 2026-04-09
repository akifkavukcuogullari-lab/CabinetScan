-- Add voice and model configuration settings
INSERT INTO platform_settings (key, value, description, is_secret) VALUES
  ('va_llm_provider', 'openai', 'LLM provider for voice agent (openai, anthropic, groq, etc.)', false),
  ('va_llm_model', 'gpt-4o', 'LLM model for voice agent (gpt-4o, gpt-4o-mini, claude-3-5-sonnet, etc.)', false),
  ('va_voice_provider', '11labs', 'Voice provider (11labs, openai, deepgram, playht, etc.)', false),
  ('va_voice_id', '21m00Tcm4TlvDq8ikWAM', 'Voice ID from the voice provider (default: Rachel from ElevenLabs)', false),
  ('va_first_message', 'Hi, this is the scheduling assistant. How are you today?', 'First message the AI says when the call connects', false)
ON CONFLICT (key) DO NOTHING;
