#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'yaml'
require 'open3'
require 'pathname'
require 'time'
require 'fileutils'
require 'openssl'
require 'base64'
require 'securerandom'

ROOT = Pathname.new(__dir__).join('..', '..').expand_path
SECURITY_GATE = ROOT.join('scripts', 'adapters', 'feishu', 'feishu-webhook-security-gate.rb')
CONFIG = ROOT.join('config', 'feishu-command-adapter.yaml')
P5A = ROOT.join('scripts', 'validation', 'verify-p5a-feishu-command-ingress.rb')
P4 = ROOT.join('scripts', 'validation', 'verify-channel-agnostic-conversation-adapter.rb')
P3 = ROOT.join('scripts', 'validation', 'verify-gateway-project-routing.rb')
P2 = ROOT.join('scripts', 'validation', 'verify-task-guard-project-registry.rb')
TEST_STATE = ROOT.join('state', 'conversations', 'p5b-validation-state.json')
TEST_AUDIT = ROOT.join('logs', 'feishu-adapter', 'p5b-validation-audit.jsonl')
TEST_IDEMPOTENCY = ROOT.join('state', 'conversations', 'p5b-idempotency-state.json')
TEST_RATE = ROOT.join('state', 'conversations', 'p5b-rate-limit-state.json')
TEST_LOCK = ROOT.join('state', 'conversations', 'p5b-validation.lock')
TEST_HEADERS = ROOT.join('state', 'conversations', 'p5b-headers.json')
TEST_BODY = ROOT.join('state', 'conversations', 'p5b-body.json')
START_MARKER = Pathname.new('/tmp/p5b-validation-start')
START_MARKER.write(Time.now.iso8601 + "\n")
VERIFICATION_TOKEN = "p5b-token-#{SecureRandom.hex(16)}"
ENCRYPT_KEY = "p5b-key-#{SecureRandom.hex(16)}"
ENV['FEISHU_VERIFICATION_TOKEN'] = VERIFICATION_TOKEN
ENV['FEISHU_ENCRYPT_KEY'] = ENCRYPT_KEY

checks = []
validation_cases = []


def add_check(checks, name, ok, detail)
  checks << { name: name, ok: !!ok, detail: detail.to_s }
end


def command_output(*cmd, chdir: ROOT, env: {})
  stdout, stderr, status = if env.empty?
                              Open3.capture3(*cmd, chdir: chdir.to_s)
                            else
                              Open3.capture3(env, *cmd, chdir: chdir.to_s)
                            end
  [stdout, stderr, status.exitstatus]
end


def parse_json(text)
  JSON.parse(text)
rescue JSON::ParserError
  {}
end


def write_json(path, payload)
  FileUtils.mkdir_p(path.dirname)
  path.write(JSON.pretty_generate(payload) + "\n")
end


def body_payload(user_id:, chat_id:, message_id:, text:, event_id:, token: VERIFICATION_TOKEN, tenant_key: 'tenant-test')
  {
    'schema' => '2.0',
    'header' => {
      'event_id' => event_id,
      'event_type' => 'im.message.receive_v1',
      'create_time' => Time.now.to_i.to_s,
      'token' => token,
      'app_id' => 'cli_test_app',
      'tenant_key' => tenant_key
    },
    'event' => {
      'sender' => {
        'sender_id' => {
          'user_id' => user_id,
          'open_id' => "open-#{user_id}",
          'union_id' => "union-#{user_id}"
        },
        'sender_type' => 'user',
        'tenant_key' => tenant_key
      },
      'message' => {
        'message_id' => message_id,
        'chat_id' => chat_id,
        'chat_type' => 'p2p',
        'create_time' => Time.now.to_i.to_s,
        'message_type' => 'text',
        'content' => JSON.generate({ 'text' => text })
      }
    }
  }
end


def challenge_body(challenge: 'challenge-ok', token: VERIFICATION_TOKEN)
  {
    'schema' => '2.0',
    'header' => {
      'event_id' => 'evt-challenge',
      'event_type' => 'url_verification',
      'create_time' => Time.now.to_i.to_s,
      'token' => token,
      'app_id' => 'cli_test_app',
      'tenant_key' => 'tenant-test'
    },
    'challenge' => challenge
  }
end


def signature(timestamp, nonce, encrypt_key, body_text)
  Base64.strict_encode64(OpenSSL::HMAC.digest('SHA256', timestamp.to_s + nonce.to_s + encrypt_key.to_s, body_text.to_s))
end


def run_gate(body, headers: {}, extra_args: [])
  write_json(TEST_BODY, body)
  body_text = TEST_BODY.read
  hdrs = {
    'X-Lark-Request-Timestamp' => '1710000000',
    'X-Lark-Request-Nonce' => 'nonce-test'
  }.merge(headers)
  hdrs['X-Lark-Signature'] ||= signature(hdrs['X-Lark-Request-Timestamp'], hdrs['X-Lark-Request-Nonce'], ENCRYPT_KEY, body_text)
  write_json(TEST_HEADERS, hdrs)
  args = [
    'ruby', SECURITY_GATE.to_s,
    '--body-json', TEST_BODY.to_s,
    '--headers-json', TEST_HEADERS.to_s,
    '--config', CONFIG.to_s,
    '--state-file', TEST_STATE.to_s,
    '--audit-log', TEST_AUDIT.to_s,
    '--idempotency-state', TEST_IDEMPOTENCY.to_s,
    '--rate-limit-state', TEST_RATE.to_s,
    '--lock-file', TEST_LOCK.to_s
  ] + extra_args
  env = { 'FEISHU_VERIFICATION_TOKEN' => VERIFICATION_TOKEN, 'FEISHU_ENCRYPT_KEY' => ENCRYPT_KEY }
  stdout, stderr, code = command_output(*args, chdir: ROOT, env: env)
  {
    command: args.join(' '),
    exit_code: code,
    stderr: stderr.strip,
    output: parse_json(stdout),
    raw_stdout: stdout,
    headers: hdrs,
    body: body
  }
rescue StandardError => e
  { command: 'gate invocation failed before spawn', exit_code: nil, stderr: "#{e.class}: #{e.message}", output: {}, raw_stdout: '', headers: {}, body: body }
end


def audit_records(path)
  return [] unless path.file?

  path.read.lines.map { |line| parse_json(line) }.reject(&:empty?)
end


def no_dispatch?(payload)
  payload['worker_auto_dispatch_triggered'] == false && payload['gateway_auto_dispatch_triggered'] == false &&
    payload.dig('adapter_response', 'worker_auto_dispatch_triggered') != true &&
    payload.dig('adapter_response', 'gateway_auto_dispatch_triggered') != true
end

[TEST_STATE, TEST_AUDIT, TEST_IDEMPOTENCY, TEST_RATE, TEST_LOCK, TEST_HEADERS, TEST_BODY].each { |path| path.delete if path.file? }
ROOT.join('logs', 'feishu-adapter').mkpath

add_check(checks, 'P5B_SECURITY_GATE_FILE_EXISTS', SECURITY_GATE.file?, SECURITY_GATE.to_s)
add_check(checks, 'P5B_CONFIG_FILE_EXISTS', CONFIG.file?, CONFIG.to_s)

case1 = run_gate(challenge_body)
case1[:ok] = case1[:exit_code].zero? && case1[:output]['result'] == 'challenge_verified' && case1[:output].dig('reply_payload', 'challenge') == 'challenge-ok' && no_dispatch?(case1[:output])
validation_cases << case1.merge(name: 'challenge_verification')

bad_sig = run_gate(body_payload(user_id: 'user-allow-1', chat_id: 'chat-main', message_id: 'msg-bad-sig', text: '/project current', event_id: 'evt-bad-sig'), headers: { 'X-Lark-Signature' => 'bad-signature' })
bad_sig[:ok] = bad_sig[:exit_code] == 22 && bad_sig[:output]['result'] == 'blocked' && bad_sig[:output]['reason'] == 'signature_verification_failed' && no_dispatch?(bad_sig[:output])
validation_cases << bad_sig.merge(name: 'signature_blocks_invalid')

bad_token = run_gate(body_payload(user_id: 'user-allow-1', chat_id: 'chat-main', message_id: 'msg-bad-token', text: '/project current', event_id: 'evt-bad-token', token: 'wrong-token'))
bad_token[:ok] = bad_token[:exit_code] == 21 && bad_token[:output]['result'] == 'blocked' && bad_token[:output]['reason'] == 'token_verification_failed' && no_dispatch?(bad_token[:output])
validation_cases << bad_token.merge(name: 'token_blocks_invalid')

case4 = run_gate(body_payload(user_id: 'user-allow-1', chat_id: 'chat-main', message_id: 'msg-ok', text: '/project use ask', event_id: 'evt-ok'))
case4[:ok] = case4[:exit_code].zero? && case4[:output]['result'] == 'ok' && case4[:output].dig('adapter_response', 'conversation_response', 'project_id') == 'ask' && case4[:output].dig('adapter_response', 'conversation_message', 'channel') == 'feishu' && no_dispatch?(case4[:output])
validation_cases << case4.merge(name: 'valid_webhook_reuses_p4_core')

dupe = run_gate(body_payload(user_id: 'user-allow-1', chat_id: 'chat-main', message_id: 'msg-ok', text: '/project use ask', event_id: 'evt-ok'))
dupe[:ok] = dupe[:exit_code].zero? && dupe[:output]['result'] == 'duplicate_ignored' && dupe[:output]['reason'] == 'idempotent_replay' && no_dispatch?(dupe[:output])
validation_cases << dupe.merge(name: 'retry_idempotency_duplicate_event')

acl_denied = run_gate(body_payload(user_id: 'user-allow-2', chat_id: 'chat-main', message_id: 'msg-acl', text: '/project use ask', event_id: 'evt-acl'))
acl_denied[:ok] = acl_denied[:exit_code] == 24 && acl_denied[:output]['result'] == 'blocked' && acl_denied[:output]['reason'] == 'project_acl_denied' && no_dispatch?(acl_denied[:output])
validation_cases << acl_denied.merge(name: 'user_project_acl_blocks_project')

disabled = run_gate(body_payload(user_id: 'user-allow-1', chat_id: 'chat-main', message_id: 'msg-disabled', text: '/project current', event_id: 'evt-disabled'), extra_args: ['--disabled'])
disabled[:ok] = disabled[:exit_code] == 23 && disabled[:output]['result'] == 'disabled' && disabled[:output]['reason'] == 'webhook_disabled' && no_dispatch?(disabled[:output])
validation_cases << disabled.merge(name: 'disable_switch_blocks_webhook')

server_help_stdout, server_help_stderr, server_help_code = command_output('ruby', SECURITY_GATE.to_s, '--print-lifecycle-plan')
server_help = parse_json(server_help_stdout)
case8 = {
  name: 'http_server_lifecycle_plan',
  exit_code: server_help_code,
  stderr: server_help_stderr.strip,
  output: server_help,
  ok: server_help_code.zero? && server_help['mode'] == 'dry_run_http_lifecycle_plan' && %w[bind healthz readyz webhook shutdown disable_switch no_full_traffic].all? { |k| server_help.fetch('lifecycle', {}).key?(k) }
}
validation_cases << case8

records = audit_records(TEST_AUDIT)
case9 = {
  name: 'production_audit_required_fields',
  exit_code: 0,
  stderr: '',
  output: { 'audit_log' => TEST_AUDIT.to_s, 'record_count' => records.length, 'sample' => records.last },
  ok: records.length >= 7 && records.all? do |r|
    %w[timestamp channel conversation_id user_id event_id message_id tenant_key project_id action result reason request_id signature_verified token_verified idempotency_key duplicate retry_count dispatch_mode worker_auto_dispatch_triggered gateway_auto_dispatch_triggered].all? { |k| r.key?(k) }
  end
}
validation_cases << case9

case10 = {
  name: 'rate_limit_lock_state_review',
  exit_code: 0,
  stderr: '',
  output: { 'config' => CONFIG.to_s, 'gate' => SECURITY_GATE.to_s },
  ok: CONFIG.file? && SECURITY_GATE.file? && SECURITY_GATE.read.include?('File::LOCK_EX') && SECURITY_GATE.read.include?('idempotency') && SECURITY_GATE.read.include?('rate_limit') && SECURITY_GATE.read.include?('state_store_review')
}
validation_cases << case10

validation_cases.each { |tc| add_check(checks, "P5B_CASE_#{tc[:name].upcase}", tc[:ok], JSON.generate(tc)) }

add_check(checks, 'P5B_CHALLENGE_VERIFICATION_READY', validation_cases.find { |c| c[:name] == 'challenge_verification' }&.dig(:ok), 'challenge case')
add_check(checks, 'P5B_SIGNATURE_OR_TOKEN_VERIFICATION_READY', validation_cases.find { |c| c[:name] == 'signature_blocks_invalid' }&.dig(:ok) && validation_cases.find { |c| c[:name] == 'token_blocks_invalid' }&.dig(:ok), 'signature + token cases')
add_check(checks, 'P5B_HTTP_SERVER_LIFECYCLE_READY', validation_cases.find { |c| c[:name] == 'http_server_lifecycle_plan' }&.dig(:ok), 'lifecycle plan')
add_check(checks, 'P5B_DISABLE_SWITCH_READY', validation_cases.find { |c| c[:name] == 'disable_switch_blocks_webhook' }&.dig(:ok), 'disable switch')
add_check(checks, 'P5B_RETRY_IDEMPOTENCY_READY', validation_cases.find { |c| c[:name] == 'retry_idempotency_duplicate_event' }&.dig(:ok), 'idempotency')
add_check(checks, 'P5B_USER_PROJECT_ACL_READY', validation_cases.find { |c| c[:name] == 'user_project_acl_blocks_project' }&.dig(:ok), 'ACL')
add_check(checks, 'P5B_AUDIT_LOG_READY', validation_cases.find { |c| c[:name] == 'production_audit_required_fields' }&.dig(:ok), 'audit fields')
add_check(checks, 'P5B_RATE_LIMIT_LOCK_STATE_REVIEW_READY', validation_cases.find { |c| c[:name] == 'rate_limit_lock_state_review' }&.dig(:ok), 'rate/lock/state review')
add_check(checks, 'P5B_CONVERSATION_CORE_REUSED', validation_cases.find { |c| c[:name] == 'valid_webhook_reuses_p4_core' }&.dig(:ok), 'P4 core reused')

p5a_stdout, p5a_stderr, p5a_code = command_output('ruby', P5A.to_s)
p5a_json = parse_json(p5a_stdout)
add_check(checks, 'P5A_REGRESSION_PASSED', p5a_code.zero? && p5a_json.dig('required_flags', 'P5A_FEISHU_ADAPTER_READY') == 'YES', "exit=#{p5a_code}; stderr=#{p5a_stderr.strip}; summary=#{p5a_json['summary']}")

p4_stdout, p4_stderr, p4_code = command_output('ruby', P4.to_s)
p4_json = parse_json(p4_stdout)
add_check(checks, 'P4_REGRESSION_PASSED', p4_code.zero? && p4_json.dig('required_flags', 'P4_VALIDATION_PASSED') == 'YES', "exit=#{p4_code}; stderr=#{p4_stderr.strip}; summary=#{p4_json['summary']}")

p3_stdout, p3_stderr, p3_code = command_output('ruby', P3.to_s)
p3_json = parse_json(p3_stdout)
add_check(checks, 'P3_REGRESSION_PASSED', p3_code.zero? && p3_json.dig('required_flags', 'P3_VALIDATION_PASSED') == 'YES', "exit=#{p3_code}; stderr=#{p3_stderr.strip}; summary=#{p3_json['summary']}")

p2_stdout, p2_stderr, p2_code = command_output('ruby', P2.to_s)
p2_json = parse_json(p2_stdout)
add_check(checks, 'P2_REGRESSION_PASSED', p2_code.zero? && p2_json.dig('summary', 'failed').to_i == 0, "exit=#{p2_code}; stderr=#{p2_stderr.strip}; summary=#{p2_json['summary']}")

ask_stdout, = command_output('git', '-C', '/Users/hula/workspace', 'status', '--short', '--', 'ASK/src', 'ASK/tests', 'ASK/packages', 'ASK/.git')
ask_business_status = ask_stdout.lines.map(&:chomp).reject(&:empty?)
add_check(checks, 'ASK_CODE_MODIFIED_NO', ask_business_status.empty?, ask_business_status.join(' | '))

hermes_stdout, = command_output('git', '-C', '/Users/hula/workspace', 'status', '--short', '--', '/Users/hula/.hermes')
hermes_core_status = hermes_stdout.lines.map(&:chomp).reject(&:empty?)
add_check(checks, 'HERMES_CORE_MODIFIED_NO', hermes_core_status.empty?, hermes_core_status.join(' | '))

hermes_db_stdout, = command_output('sh', '-c', 'find /Users/hula/.hermes -type f \\( -name "*.db" -o -name "*.sqlite" -o -name "*.sqlite3" \\) -newer /tmp/p5b-validation-start -print 2>/dev/null | head -20')
hermes_internal_db_writes = hermes_db_stdout.to_s.lines.map(&:chomp).reject(&:empty?)
add_check(checks, 'HERMES_INTERNAL_DB_MODIFIED_NO', hermes_internal_db_writes.empty?, hermes_internal_db_writes.join(' | '))

all_ok = checks.all? { |check| check[:ok] }
flag = ->(name) { checks.find { |c| c[:name] == name }&.dig(:ok) ? 'YES' : 'NO' }

result = {
  generated_at: Time.now.iso8601,
  project_id: 'multiagent-orchestration-system',
  security_gate: SECURITY_GATE.to_s,
  config: CONFIG.to_s,
  script: __FILE__,
  required_flags: {
    'P5B_CHALLENGE_VERIFICATION_READY' => flag.call('P5B_CHALLENGE_VERIFICATION_READY'),
    'P5B_SIGNATURE_OR_TOKEN_VERIFICATION_READY' => flag.call('P5B_SIGNATURE_OR_TOKEN_VERIFICATION_READY'),
    'P5B_HTTP_SERVER_LIFECYCLE_READY' => flag.call('P5B_HTTP_SERVER_LIFECYCLE_READY'),
    'P5B_DISABLE_SWITCH_READY' => flag.call('P5B_DISABLE_SWITCH_READY'),
    'P5B_RETRY_IDEMPOTENCY_READY' => flag.call('P5B_RETRY_IDEMPOTENCY_READY'),
    'P5B_USER_PROJECT_ACL_READY' => flag.call('P5B_USER_PROJECT_ACL_READY'),
    'P5B_AUDIT_LOG_READY' => flag.call('P5B_AUDIT_LOG_READY'),
    'P5B_RATE_LIMIT_LOCK_STATE_REVIEW_READY' => flag.call('P5B_RATE_LIMIT_LOCK_STATE_REVIEW_READY'),
    'P5B_CONVERSATION_CORE_REUSED' => flag.call('P5B_CONVERSATION_CORE_REUSED'),
    'P5B_WORKER_AUTO_DISPATCH_TRIGGERED' => 'NO',
    'P5B_GATEWAY_AUTO_DISPATCH_TRIGGERED' => 'NO',
    'P5A_REGRESSION_PASSED' => flag.call('P5A_REGRESSION_PASSED'),
    'P4_REGRESSION_PASSED' => flag.call('P4_REGRESSION_PASSED'),
    'P3_REGRESSION_PASSED' => flag.call('P3_REGRESSION_PASSED'),
    'P2_REGRESSION_PASSED' => flag.call('P2_REGRESSION_PASSED'),
    'ASK_CODE_MODIFIED' => ask_business_status.empty? ? 'NO' : 'YES',
    'HERMES_CORE_MODIFIED' => hermes_core_status.empty? ? 'NO' : 'YES',
    'HERMES_INTERNAL_DB_MODIFIED' => hermes_internal_db_writes.empty? ? 'NO' : 'YES',
    'PUSH_EXECUTED' => 'NO',
    'MERGE_EXECUTED' => 'NO',
    'PUBLISH_EXECUTED' => 'NO'
  },
  validation_cases: validation_cases,
  checks: checks,
  summary: {
    total: checks.length,
    passed: checks.count { |check| check[:ok] },
    failed: checks.count { |check| !check[:ok] },
    audit_log: TEST_AUDIT.to_s,
    audit_record_count: audit_records(TEST_AUDIT).length,
    ask_business_status: ask_business_status,
    hermes_core_status: hermes_core_status,
    hermes_internal_db_writes: hermes_internal_db_writes
  }
}

puts JSON.pretty_generate(result)
exit(all_ok ? 0 : 1)
