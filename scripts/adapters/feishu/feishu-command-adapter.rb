#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'yaml'
require 'optparse'
require 'open3'
require 'pathname'
require 'time'
require 'fileutils'

ROOT = Pathname.new(__dir__).join('..', '..', '..').expand_path
CORE = ROOT.join('scripts', 'conversation', 'project-conversation-router.rb')
STATE_ROOT = ROOT.join('state', 'conversations').expand_path
LOG_ROOT = ROOT.join('logs', 'feishu-adapter').expand_path
SUPPORTED_PROJECT_IDS = %w[ask project-agent-router].freeze
SAFE_COMMAND_PATTERNS = [
  %r{\A/project\s+list\z}i,
  %r{\A/project\s+current\z}i,
  %r{\A/project\s+clear\z}i,
  %r{\A/project\s+use\s+(ask|project-agent-router)\z}i,
  %r{\A/project\s+default\s+(ask|project-agent-router)\z}i,
  %r{\A/system\s+status\z}i,
  %r{\A/orchestration\s+status\z}i
].freeze

options = {
  feishu_event_json: nil,
  config: ROOT.join('config', 'feishu-command-adapter.yaml').to_s,
  state_file: nil,
  audit_log: nil,
  rate_limit_state: nil,
  lock_file: nil,
  disabled: false
}

OptionParser.new do |opts|
  opts.banner = 'Usage: feishu-command-adapter.rb --feishu-event-json PATH [options]'
  opts.on('--feishu-event-json PATH', 'Feishu event JSON file') { |v| options[:feishu_event_json] = v }
  opts.on('--config PATH', 'Adapter YAML config') { |v| options[:config] = v }
  opts.on('--state-file PATH', 'Conversation core state file under project state/conversations') { |v| options[:state_file] = v }
  opts.on('--audit-log PATH', 'Audit log JSONL under project logs/feishu-adapter') { |v| options[:audit_log] = v }
  opts.on('--rate-limit-state PATH', 'Rate-limit state file under project state/conversations') { |v| options[:rate_limit_state] = v }
  opts.on('--lock-file PATH', 'Lock file under project state/conversations') { |v| options[:lock_file] = v }
  opts.on('--disabled', 'Fast disable / rollback switch') { options[:disabled] = true }
end.parse!


def load_config(path)
  YAML.safe_load(Pathname.new(path).read, aliases: false)
rescue StandardError => e
  warn "config_error=#{e.class}: #{e.message}"
  {}
end


def safe_project_path(path, root, label)
  candidate = Pathname.new(path).expand_path
  unless candidate.to_s.start_with?(root.to_s + '/')
    raise ArgumentError, "#{label}_must_be_under=#{root}"
  end
  candidate
end


def read_json_file(path)
  JSON.parse(Pathname.new(path).read)
end


def parse_feishu_text(content)
  parsed = JSON.parse(content.to_s)
  parsed['text'].to_s.strip
rescue JSON::ParserError
  content.to_s.strip
end


def feishu_to_conversation_message(event)
  message = event.fetch('event').fetch('message')
  sender = event.fetch('event').fetch('sender')
  sender_id = sender.fetch('sender_id')
  user_id = sender_id['user_id'] || sender_id['open_id'] || sender_id['union_id']
  timestamp = message['create_time'] ? Time.at(message['create_time'].to_i).iso8601 : Time.now.iso8601
  {
    'channel' => 'feishu',
    'conversation_id' => message.fetch('chat_id'),
    'user_id' => user_id,
    'message_id' => message.fetch('message_id'),
    'text' => parse_feishu_text(message.fetch('content')),
    'timestamp' => timestamp,
    'metadata' => {
      'raw_platform' => 'feishu',
      'tenant_key' => event.dig('header', 'tenant_key') || sender['tenant_key'],
      'chat_type' => message['chat_type'],
      'message_type' => message['message_type'],
      'event_id' => event.dig('header', 'event_id')
    }
  }
end


def valid_command?(text)
  return false if text.bytesize > 256
  return false if text.match?(/[;&|`$<>\\]/)

  SAFE_COMMAND_PATTERNS.any? { |pattern| text.match?(pattern) }
end


def load_json_state(path)
  path.file? ? JSON.parse(path.read) : {}
rescue JSON::ParserError
  {}
end


def save_json_state(path, payload)
  FileUtils.mkdir_p(path.dirname)
  path.write(JSON.pretty_generate(payload) + "\n")
end


def rate_limited?(path, key, max_commands, window_seconds, now)
  state = load_json_state(path)
  records = state.fetch(key, []).select { |ts| now - ts.to_i < window_seconds }
  limited = records.length >= max_commands
  records << now unless limited
  state[key] = records
  save_json_state(path, state)
  limited
end


def call_core(message, state_file)
  stdout, stderr, status = Open3.capture3('ruby', CORE.to_s, '--message-json', JSON.generate(message), '--state-file', state_file.to_s, chdir: ROOT.to_s)
  [stdout.empty? ? {} : JSON.parse(stdout), stderr, status.exitstatus]
rescue StandardError => e
  [{ 'mode' => 'blocked', 'project_id' => 'blocked', 'response_text' => "conversation core error: #{e.class}: #{e.message}", 'worker_auto_dispatch_triggered' => false, 'gateway_auto_dispatch_triggered' => false }, '', 10]
end


def feishu_reply_payload(chat_id, text)
  {
    'receive_id_type' => 'chat_id',
    'receive_id' => chat_id,
    'msg_type' => 'text',
    'content' => JSON.generate({ 'text' => text.to_s })
  }
end


def adapter_response(result:, reason:, conversation_message:, conversation_response:, reply_text:, exit_code:)
  chat_id = conversation_message && conversation_message['conversation_id'] || 'chat-unknown'
  {
    'channel' => 'feishu',
    'result' => result,
    'reason' => reason,
    'conversation_message' => conversation_message,
    'conversation_response' => conversation_response,
    'reply_payload' => feishu_reply_payload(chat_id, reply_text),
    'worker_auto_dispatch_triggered' => false,
    'gateway_auto_dispatch_triggered' => false,
    'exit_code' => exit_code
  }
end


def append_audit(path, record)
  FileUtils.mkdir_p(path.dirname)
  File.open(path, 'a') { |file| file.puts(JSON.generate(record)) }
end


def audit_record(message:, response:, action:, result:, reason:)
  {
    'timestamp' => Time.now.iso8601,
    'channel' => 'feishu',
    'conversation_id' => message && message['conversation_id'],
    'user_id' => message && message['user_id'],
    'message_id' => message && message['message_id'],
    'project_id' => response && response['project_id'],
    'action' => action,
    'result' => result,
    'reason' => reason,
    'dispatch_mode' => response && response['dispatch_mode'],
    'worker_auto_dispatch_triggered' => false,
    'gateway_auto_dispatch_triggered' => false
  }
end


def action_from_text(text)
  case text.to_s
  when %r{\A/project\s+list\z}i then 'project_list'
  when %r{\A/project\s+current\z}i then 'project_current'
  when %r{\A/project\s+clear\z}i then 'project_clear'
  when %r{\A/project\s+use\s+}i then 'project_use'
  when %r{\A/project\s+default\s+}i then 'project_default'
  when %r{\A/system\s+status\z}i then 'system_status'
  when %r{\A/orchestration\s+status\z}i then 'orchestration_status'
  else 'unknown'
  end
end

begin
  raise ArgumentError, 'missing --feishu-event-json' if options[:feishu_event_json].nil?

  config = load_config(options[:config])
  state_file = safe_project_path(options[:state_file] || config.dig('state', 'conversation_state_file') || ROOT.join('state', 'conversations', 'feishu-command-state.json'), STATE_ROOT, 'state_file')
  rate_file = safe_project_path(options[:rate_limit_state] || config.dig('state', 'rate_limit_state_file') || ROOT.join('state', 'conversations', 'feishu-rate-limit-state.json'), STATE_ROOT, 'rate_limit_state')
  lock_file = safe_project_path(options[:lock_file] || config.dig('state', 'lock_file') || ROOT.join('state', 'conversations', 'feishu-command-state.lock'), STATE_ROOT, 'lock_file')
  audit_log = safe_project_path(options[:audit_log] || config.dig('audit', 'log_file') || ROOT.join('logs', 'feishu-adapter', 'feishu-command-audit.jsonl'), LOG_ROOT, 'audit_log')

  event = read_json_file(options[:feishu_event_json])
  message = feishu_to_conversation_message(event)
  allowed_users = Array(config['allowed_user_ids'])
  rate_cfg = config['rate_limit'] || {}
  max_commands = (rate_cfg['max_commands'] || 3).to_i
  window_seconds = (rate_cfg['window_seconds'] || 60).to_i
  action = action_from_text(message['text'])
  response = nil
  result = 'ok'
  reason = 'ok'
  exit_code = 0

  FileUtils.mkdir_p(lock_file.dirname)
  File.open(lock_file, File::RDWR | File::CREAT, 0o600) do |lock|
    lock.flock(File::LOCK_EX)

    if options[:disabled] || config['feature_enabled'] == false
      result = 'disabled'
      reason = 'adapter_disabled'
      exit_code = 11
      response = { 'mode' => 'blocked', 'project_id' => nil, 'response_text' => 'Feishu 项目命令入口已禁用。', 'worker_auto_dispatch_triggered' => false, 'gateway_auto_dispatch_triggered' => false }
    elsif !allowed_users.include?(message['user_id'])
      result = 'blocked'
      reason = 'user_not_whitelisted'
      exit_code = 12
      response = { 'mode' => 'blocked', 'project_id' => nil, 'response_text' => '你暂未在 P5a 小流量白名单内。', 'worker_auto_dispatch_triggered' => false, 'gateway_auto_dispatch_triggered' => false }
    elsif !valid_command?(message['text'])
      result = 'blocked'
      reason = 'input_validation_failed'
      exit_code = 13
      response = { 'mode' => 'blocked', 'project_id' => nil, 'response_text' => '命令未通过输入校验；P5a 仅支持项目管理类命令。', 'worker_auto_dispatch_triggered' => false, 'gateway_auto_dispatch_triggered' => false }
    elsif rate_limited?(rate_file, "#{message['conversation_id']}:#{message['user_id']}", max_commands, window_seconds, Time.now.to_i)
      result = 'rate_limited'
      reason = 'rate_limited'
      exit_code = 14
      response = { 'mode' => 'blocked', 'project_id' => nil, 'response_text' => '命令过于频繁，请稍后再试。', 'worker_auto_dispatch_triggered' => false, 'gateway_auto_dispatch_triggered' => false }
    else
      response, core_stderr, core_exit = call_core(message, state_file)
      result = core_exit.zero? ? 'ok' : 'blocked'
      reason = core_exit.zero? ? 'ok' : 'conversation_core_blocked'
      exit_code = core_exit.zero? ? 0 : 10
    end

    append_audit(audit_log, audit_record(message: message, response: response, action: action, result: result, reason: reason))
  end

  reply_text = response['response_text'] || reason
  payload = adapter_response(result: result, reason: reason, conversation_message: message, conversation_response: response, reply_text: reply_text, exit_code: exit_code)
  puts JSON.pretty_generate(payload)
  exit exit_code
rescue StandardError => e
  warn "feishu_adapter_error=#{e.class}: #{e.message}"
  fallback_message = { 'channel' => 'feishu', 'conversation_id' => 'chat-unknown', 'user_id' => nil, 'message_id' => nil, 'text' => nil }
  fallback_response = { 'mode' => 'blocked', 'project_id' => nil, 'response_text' => "Feishu adapter error: #{e.class}: #{e.message}", 'worker_auto_dispatch_triggered' => false, 'gateway_auto_dispatch_triggered' => false }
  puts JSON.pretty_generate(adapter_response(result: 'blocked', reason: 'adapter_error', conversation_message: fallback_message, conversation_response: fallback_response, reply_text: fallback_response['response_text'], exit_code: 15))
  exit 15
end
