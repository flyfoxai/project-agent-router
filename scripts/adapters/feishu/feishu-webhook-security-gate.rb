#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'yaml'
require 'optparse'
require 'open3'
require 'pathname'
require 'time'
require 'fileutils'
require 'openssl'
require 'base64'
require 'securerandom'

ROOT = Pathname.new(__dir__).join('..', '..', '..').expand_path
P5A_ADAPTER = ROOT.join('scripts', 'adapters', 'feishu', 'feishu-command-adapter.rb')
STATE_ROOT = ROOT.join('state', 'conversations').expand_path
LOG_ROOT = ROOT.join('logs', 'feishu-adapter').expand_path
SAFE_PROJECT_IDS = %w[ask project-agent-router].freeze

options = {
  body_json: nil,
  headers_json: nil,
  config: ROOT.join('config', 'feishu-command-adapter.yaml').to_s,
  state_file: nil,
  audit_log: nil,
  idempotency_state: nil,
  rate_limit_state: nil,
  lock_file: nil,
  disabled: false,
  print_lifecycle_plan: false
}

OptionParser.new do |opts|
  opts.banner = 'Usage: feishu-webhook-security-gate.rb --body-json PATH --headers-json PATH [options]'
  opts.on('--body-json PATH', 'Webhook body JSON file') { |v| options[:body_json] = v }
  opts.on('--headers-json PATH', 'Webhook headers JSON file') { |v| options[:headers_json] = v }
  opts.on('--config PATH', 'Adapter YAML config') { |v| options[:config] = v }
  opts.on('--state-file PATH', 'Conversation state file under project state/conversations') { |v| options[:state_file] = v }
  opts.on('--audit-log PATH', 'Audit JSONL under project logs/feishu-adapter') { |v| options[:audit_log] = v }
  opts.on('--idempotency-state PATH', 'Idempotency state under project state/conversations') { |v| options[:idempotency_state] = v }
  opts.on('--rate-limit-state PATH', 'Rate-limit state under project state/conversations') { |v| options[:rate_limit_state] = v }
  opts.on('--lock-file PATH', 'Lock file under project state/conversations') { |v| options[:lock_file] = v }
  opts.on('--disabled', 'Fast disable / rollback switch') { options[:disabled] = true }
  opts.on('--print-lifecycle-plan', 'Print dry-run HTTP lifecycle plan') { options[:print_lifecycle_plan] = true }
end.parse!


def load_config(path)
  YAML.safe_load(Pathname.new(path).read, aliases: false)
rescue StandardError => e
  warn "config_error=#{e.class}: #{e.message}"
  {}
end


def resolved_secret(env_name, explicit_value)
  value = explicit_value.to_s
  return value unless value.empty?

  env_name = env_name.to_s
  return '' if env_name.empty?

  ENV.fetch(env_name, '')
end


def safe_project_path(path, root, label)
  candidate = Pathname.new(path).expand_path
  unless candidate.to_s.start_with?(root.to_s + '/')
    raise ArgumentError, "#{label}_must_be_under=#{root}"
  end
  candidate
end


def load_json(path)
  JSON.parse(Pathname.new(path).read)
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


def append_audit(path, record)
  FileUtils.mkdir_p(path.dirname)
  File.open(path, 'a') { |file| file.puts(JSON.generate(record)) }
end


def header(headers, name)
  headers[name] || headers[name.downcase] || headers[name.upcase]
end


def expected_signature(timestamp, nonce, encrypt_key, body_text)
  Base64.strict_encode64(OpenSSL::HMAC.digest('SHA256', timestamp.to_s + nonce.to_s + encrypt_key.to_s, body_text.to_s))
end


def signature_valid?(headers, security, body_text)
  return true unless security['signature_required']

  timestamp = header(headers, 'X-Lark-Request-Timestamp')
  nonce = header(headers, 'X-Lark-Request-Nonce')
  actual = header(headers, 'X-Lark-Signature')
  return false if [timestamp, nonce, actual].any? { |v| v.to_s.empty? }

  encrypt_key = resolved_secret(security['encrypt_key_env'], security['encrypt_key'])
  return false if encrypt_key.to_s.empty?

  expected = expected_signature(timestamp, nonce, encrypt_key, body_text)
  OpenSSL.fixed_length_secure_compare(expected, actual) rescue expected == actual
end


def token_valid?(body, security)
  return true unless security['token_required']

  expected = resolved_secret(security['verification_token_env'], security['verification_token'])
  token = body.dig('header', 'token') || body['token']
  !expected.empty? && token.to_s == expected
end


def event_id(body)
  body.dig('header', 'event_id') || body['uuid'] || body.dig('event', 'message', 'message_id') || SecureRandom.uuid
end


def event_type(body)
  body.dig('header', 'event_type') || body['type']
end


def idempotency_key(body)
  [body.dig('header', 'tenant_key'), event_id(body)].compact.join(':')
end


def duplicate_event?(path, key, ttl_seconds, now)
  state = load_json_state(path)
  state.delete_if { |_k, record| now - record.fetch('first_seen_at', 0).to_i > ttl_seconds }
  duplicate = state.key?(key)
  if duplicate
    state[key]['retry_count'] = state[key].fetch('retry_count', 0).to_i + 1
    state[key]['last_seen_at'] = now
  else
    state[key] = { 'first_seen_at' => now, 'last_seen_at' => now, 'retry_count' => 0 }
  end
  save_json_state(path, state)
  [duplicate, state[key].fetch('retry_count', 0)]
end


def parse_project_from_text(body)
  content = body.dig('event', 'message', 'content').to_s
  text = begin
    JSON.parse(content)['text'].to_s
  rescue JSON::ParserError
    content
  end
  text[/\A\/project\s+(?:use|default)\s+([^\s]+)\z/i, 1]
end


def user_id_from_body(body)
  body.dig('event', 'sender', 'sender_id', 'user_id') || body.dig('event', 'sender', 'sender_id', 'open_id') || body.dig('event', 'sender', 'sender_id', 'union_id')
end


def acl_allowed?(body, config)
  project = parse_project_from_text(body)
  return true if project.nil? || project.empty?
  return false unless SAFE_PROJECT_IDS.include?(project)

  user_id = user_id_from_body(body)
  acl = config['user_project_acl'] || {}
  Array(acl[user_id]).include?(project)
end


def action_from_body(body)
  text = begin
    JSON.parse(body.dig('event', 'message', 'content').to_s)['text'].to_s
  rescue JSON::ParserError
    body.dig('event', 'message', 'content').to_s
  end
  case text
  when %r{\A/project\s+list\z}i then 'project_list'
  when %r{\A/project\s+current\z}i then 'project_current'
  when %r{\A/project\s+clear\z}i then 'project_clear'
  when %r{\A/project\s+use\s+}i then 'project_use'
  when %r{\A/project\s+default\s+}i then 'project_default'
  when %r{\A/system\s+status\z}i then 'system_status'
  when %r{\A/orchestration\s+status\z}i then 'orchestration_status'
  when '' then 'challenge'
  else 'unknown'
  end
end


def feishu_reply(chat_id, text)
  {
    'receive_id_type' => 'chat_id',
    'receive_id' => chat_id || 'chat-unknown',
    'msg_type' => 'text',
    'content' => JSON.generate({ 'text' => text.to_s })
  }
end


def blocked_payload(result:, reason:, body:, exit_code:, adapter_response: nil, reply_text: nil, extra: {})
  chat_id = body.dig('event', 'message', 'chat_id')
  {
    'channel' => 'feishu',
    'result' => result,
    'reason' => reason,
    'event_id' => event_id(body),
    'adapter_response' => adapter_response,
    'reply_payload' => reply_text ? feishu_reply(chat_id, reply_text) : nil,
    'worker_auto_dispatch_triggered' => false,
    'gateway_auto_dispatch_triggered' => false,
    'exit_code' => exit_code
  }.merge(extra)
end


def audit_record(body:, headers:, response:, result:, reason:, action:, signature_verified:, token_verified:, idempotency_key:, duplicate:, retry_count:, request_id:)
  adapter = response['adapter_response'] || {}
  conversation_response = adapter['conversation_response'] || {}
  message = adapter['conversation_message'] || {}
  {
    'timestamp' => Time.now.iso8601,
    'channel' => 'feishu',
    'conversation_id' => message['conversation_id'] || body.dig('event', 'message', 'chat_id'),
    'user_id' => message['user_id'] || user_id_from_body(body),
    'event_id' => event_id(body),
    'message_id' => message['message_id'] || body.dig('event', 'message', 'message_id'),
    'tenant_key' => body.dig('header', 'tenant_key') || body.dig('event', 'sender', 'tenant_key'),
    'project_id' => conversation_response['project_id'],
    'action' => action,
    'result' => result,
    'reason' => reason,
    'request_id' => request_id,
    'signature_verified' => signature_verified,
    'token_verified' => token_verified,
    'idempotency_key' => idempotency_key,
    'duplicate' => duplicate,
    'retry_count' => retry_count,
    'dispatch_mode' => conversation_response['dispatch_mode'],
    'worker_auto_dispatch_triggered' => false,
    'gateway_auto_dispatch_triggered' => false
  }
end


def call_p5a_adapter(body_path:, config:, state_file:, audit_log:, rate_limit_state:, lock_file:)
  # The webhook gate already holds the outer request lock. Use distinct inner
  # adapter lock/audit files to avoid self-deadlock and prevent P5a audit schema
  # from mixing into the P5b production-readiness audit log.
  adapter_lock_file = lock_file.dirname.join('feishu-command-adapter-inner.lock')
  adapter_audit_log = audit_log.dirname.join('feishu-command-adapter-inner-audit.jsonl')
  stdout, stderr, status = Open3.capture3(
    'ruby', P5A_ADAPTER.to_s,
    '--feishu-event-json', body_path.to_s,
    '--config', config.to_s,
    '--state-file', state_file.to_s,
    '--audit-log', adapter_audit_log.to_s,
    '--rate-limit-state', rate_limit_state.to_s,
    '--lock-file', adapter_lock_file.to_s,
    chdir: ROOT.to_s
  )
  [stdout.empty? ? {} : JSON.parse(stdout), stderr, status.exitstatus]
rescue StandardError => e
  [{ 'result' => 'blocked', 'reason' => "adapter_error: #{e.class}: #{e.message}", 'worker_auto_dispatch_triggered' => false, 'gateway_auto_dispatch_triggered' => false }, '', 15]
end


def lifecycle_plan(config)
  deployment = config['deployment'] || {}
  {
    'mode' => 'dry_run_http_lifecycle_plan',
    'lifecycle' => {
      'bind' => deployment['bind'] || '127.0.0.1:0',
      'healthz' => deployment['healthz'] || '/healthz',
      'readyz' => deployment['readyz'] || '/readyz',
      'webhook' => deployment['webhook'] || '/feishu/events',
      'shutdown' => deployment['shutdown'] || 'graceful_sigterm',
      'disable_switch' => deployment['disable_switch'] || 'config.webhook_enabled=false or --disabled',
      'no_full_traffic' => deployment.fetch('no_full_traffic', true)
    },
    'manual_dispatch_only' => config['manual_dispatch_only'] == true,
    'worker_auto_dispatch_triggered' => false,
    'gateway_auto_dispatch_triggered' => false,
    'state_store_review' => {
      'rate_limit' => 'file-backed JSON; safe only for small traffic; production needs external atomic store or single-process queue',
      'lock' => 'File.flock(File::LOCK_EX) protects local process writes only; production multi-host needs distributed lock',
      'idempotency' => 'file-backed JSON with TTL cleanup; production needs durable replay store'
    }
  }
end

begin
  config = load_config(options[:config])
  if options[:print_lifecycle_plan]
    puts JSON.pretty_generate(lifecycle_plan(config))
    exit 0
  end

  raise ArgumentError, 'missing --body-json' if options[:body_json].nil?
  raise ArgumentError, 'missing --headers-json' if options[:headers_json].nil?

  state_file = safe_project_path(options[:state_file] || config.dig('state', 'conversation_state_file') || ROOT.join('state', 'conversations', 'feishu-command-state.json'), STATE_ROOT, 'state_file')
  rate_file = safe_project_path(options[:rate_limit_state] || config.dig('state', 'rate_limit_state_file') || ROOT.join('state', 'conversations', 'feishu-rate-limit-state.json'), STATE_ROOT, 'rate_limit_state')
  idem_file = safe_project_path(options[:idempotency_state] || config.dig('state', 'idempotency_state_file') || ROOT.join('state', 'conversations', 'feishu-idempotency-state.json'), STATE_ROOT, 'idempotency_state')
  lock_file = safe_project_path(options[:lock_file] || config.dig('state', 'lock_file') || ROOT.join('state', 'conversations', 'feishu-command-state.lock'), STATE_ROOT, 'lock_file')
  audit_log = safe_project_path(options[:audit_log] || config.dig('audit', 'log_file') || ROOT.join('logs', 'feishu-adapter', 'feishu-command-audit.jsonl'), LOG_ROOT, 'audit_log')

  body_path = Pathname.new(options[:body_json]).expand_path
  headers = load_json(options[:headers_json])
  body = load_json(body_path)
  body_text = body_path.read
  security = config['webhook_security'] || {}
  live_disable_env = ENV['FEISHU_WEBHOOK_DISABLED'].to_s == '1'
  config_enabled = config['webhook_enabled'] != false && config['feature_enabled'] != false
  action = action_from_body(body)
  request_id = header(headers, 'X-Request-Id') || header(headers, 'X-Lark-Request-Nonce') || SecureRandom.uuid
  signature_verified = signature_valid?(headers, security, body_text)
  token_verified = token_valid?(body, security)
  idem_key = idempotency_key(body)
  duplicate = false
  retry_count = 0
  response = nil
  result = 'ok'
  reason = 'ok'
  exit_code = 0

  FileUtils.mkdir_p(lock_file.dirname)
  File.open(lock_file, File::RDWR | File::CREAT, 0o600) do |lock|
    lock.flock(File::LOCK_EX)

    if options[:disabled] || live_disable_env || !config_enabled
      result = 'disabled'
      reason = 'webhook_disabled'
      exit_code = 23
      response = blocked_payload(result: result, reason: reason, body: body, exit_code: exit_code, reply_text: 'Feishu webhook 入口已禁用。')
    elsif !token_verified
      result = 'blocked'
      reason = 'token_verification_failed'
      exit_code = 21
      response = blocked_payload(result: result, reason: reason, body: body, exit_code: exit_code, reply_text: 'Feishu token 校验失败。')
    elsif !signature_verified
      result = 'blocked'
      reason = 'signature_verification_failed'
      exit_code = 22
      response = blocked_payload(result: result, reason: reason, body: body, exit_code: exit_code, reply_text: 'Feishu signature 校验失败。')
    elsif Array(security['challenge_event_types']).include?(event_type(body)) || body.key?('challenge')
      result = 'challenge_verified'
      reason = 'challenge_verified'
      response = blocked_payload(result: result, reason: reason, body: body, exit_code: 0, reply_text: nil, extra: { 'reply_payload' => { 'challenge' => body['challenge'] } })
    else
      duplicate, retry_count = duplicate_event?(idem_file, idem_key, (config.dig('idempotency', 'ttl_seconds') || 86_400).to_i, Time.now.to_i)
      if duplicate
        result = 'duplicate_ignored'
        reason = 'idempotent_replay'
        response = blocked_payload(result: result, reason: reason, body: body, exit_code: 0, reply_text: '重复事件已忽略。')
      elsif !acl_allowed?(body, config)
        result = 'blocked'
        reason = 'project_acl_denied'
        exit_code = 24
        response = blocked_payload(result: result, reason: reason, body: body, exit_code: exit_code, reply_text: '用户无该项目权限。')
      else
        adapter_response, _adapter_stderr, adapter_exit = call_p5a_adapter(body_path: body_path, config: options[:config], state_file: state_file, audit_log: audit_log, rate_limit_state: rate_file, lock_file: lock_file)
        result = adapter_exit.zero? ? 'ok' : adapter_response.fetch('result', 'blocked')
        reason = adapter_exit.zero? ? 'ok' : adapter_response.fetch('reason', 'adapter_blocked')
        exit_code = adapter_exit.zero? ? 0 : adapter_exit
        response = {
          'channel' => 'feishu',
          'result' => result,
          'reason' => reason,
          'event_id' => event_id(body),
          'adapter_response' => adapter_response,
          'reply_payload' => adapter_response['reply_payload'],
          'worker_auto_dispatch_triggered' => false,
          'gateway_auto_dispatch_triggered' => false,
          'exit_code' => exit_code
        }
      end
    end

    append_audit(audit_log, audit_record(body: body, headers: headers, response: response, result: result, reason: reason, action: action, signature_verified: signature_verified, token_verified: token_verified, idempotency_key: idem_key, duplicate: duplicate, retry_count: retry_count, request_id: request_id))
  end

  puts JSON.pretty_generate(response)
  exit exit_code
rescue StandardError => e
  warn "feishu_webhook_security_gate_error=#{e.class}: #{e.message}"
  fallback = {
    'channel' => 'feishu',
    'result' => 'blocked',
    'reason' => 'security_gate_error',
    'error' => "#{e.class}: #{e.message}",
    'worker_auto_dispatch_triggered' => false,
    'gateway_auto_dispatch_triggered' => false,
    'exit_code' => 25
  }
  puts JSON.pretty_generate(fallback)
  exit 25
end
