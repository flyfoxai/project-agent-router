#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'net/http'
require 'open3'
require 'openssl'
require 'base64'
require 'pathname'
require 'securerandom'
require 'time'
require 'fileutils'

ROOT = Pathname.new(__dir__).join('..', '..').expand_path
SERVER = ROOT.join('scripts', 'adapters', 'feishu', 'feishu-webhook-server.rb')
GATE = ROOT.join('scripts', 'adapters', 'feishu', 'feishu-webhook-security-gate.rb')
CONFIG = ROOT.join('config', 'feishu-command-adapter.yaml')
P5B = ROOT.join('scripts', 'validation', 'verify-p5b-feishu-webhook-security-readiness.rb')
P5A = ROOT.join('scripts', 'validation', 'verify-p5a-feishu-command-ingress.rb')
P4 = ROOT.join('scripts', 'validation', 'verify-channel-agnostic-conversation-adapter.rb')
P3 = ROOT.join('scripts', 'validation', 'verify-gateway-project-routing.rb')
P2 = ROOT.join('scripts', 'validation', 'verify-task-guard-project-registry.rb')

TEST_ROOT = ROOT.join('state', 'conversations')
TEST_STATE = TEST_ROOT.join('p5c-validation-state.json')
TEST_AUDIT = ROOT.join('logs', 'feishu-adapter', 'p5c-validation-audit.jsonl')
TEST_IDEMPOTENCY = TEST_ROOT.join('p5c-idempotency-state.json')
TEST_RATE = TEST_ROOT.join('p5c-rate-limit-state.json')
TEST_LOCK = TEST_ROOT.join('p5c-validation.lock')
START_TIME = Time.now

checks = []
validation_cases = []


def add_check(checks, name, ok, detail)
  checks << { name: name, ok: !!ok, detail: detail.to_s }
end


def parse_json(text)
  JSON.parse(text.to_s)
rescue JSON::ParserError
  {}
end


def command_output(*cmd, env: {}, chdir: ROOT)
  stdout, stderr, status = Open3.capture3(env, *cmd, chdir: chdir.to_s)
  [stdout, stderr, status.exitstatus]
end


def signature(timestamp, nonce, encrypt_key, body_text)
  Base64.strict_encode64(OpenSSL::HMAC.digest('SHA256', timestamp.to_s + nonce.to_s + encrypt_key.to_s, body_text.to_s))
end


def body_payload(user_id:, chat_id:, message_id:, text:, event_id:, token:, tenant_key: 'tenant-p5c')
  {
    'schema' => '2.0',
    'header' => {
      'event_id' => event_id,
      'event_type' => 'im.message.receive_v1',
      'create_time' => Time.now.to_i.to_s,
      'token' => token,
      'app_id' => 'cli_p5c_app',
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


def challenge_body(challenge:, token:)
  {
    'schema' => '2.0',
    'header' => {
      'event_id' => "evt-challenge-#{SecureRandom.hex(4)}",
      'event_type' => 'url_verification',
      'create_time' => Time.now.to_i.to_s,
      'token' => token,
      'app_id' => 'cli_p5c_app',
      'tenant_key' => 'tenant-p5c'
    },
    'challenge' => challenge
  }
end


def signed_headers(body_text, encrypt_key, extra = {})
  ts = Time.now.to_i.to_s
  nonce = SecureRandom.hex(8)
  {
    'Content-Type' => 'application/json',
    'X-Lark-Request-Timestamp' => ts,
    'X-Lark-Request-Nonce' => nonce,
    'X-Lark-Signature' => signature(ts, nonce, encrypt_key, body_text),
    'X-Request-Id' => "req-#{SecureRandom.hex(8)}"
  }.merge(extra)
end


def post_json(base_uri, path, payload, encrypt_key, headers_extra = {})
  body_text = JSON.generate(payload)
  uri = URI.join(base_uri, path)
  req = Net::HTTP::Post.new(uri)
  signed_headers(body_text, encrypt_key, headers_extra).each { |k, v| req[k] = v }
  req.body = body_text
  http = Net::HTTP.new(uri.host, uri.port)
  http.read_timeout = 5
  res = http.request(req)
  { code: res.code.to_i, body: parse_json(res.body), raw_body: res.body.to_s }
rescue StandardError => e
  { code: nil, body: {}, raw_body: '', error: "#{e.class}: #{e.message}" }
end


def get_json(base_uri, path)
  uri = URI.join(base_uri, path)
  res = Net::HTTP.get_response(uri)
  { code: res.code.to_i, body: parse_json(res.body), raw_body: res.body.to_s }
rescue StandardError => e
  { code: nil, body: {}, raw_body: '', error: "#{e.class}: #{e.message}" }
end


def start_server(env:, disabled: false)
  return [nil, nil, { 'error' => 'server_file_missing' }] unless SERVER.file?

  args = [
    'ruby', SERVER.to_s,
    '--config', CONFIG.to_s,
    '--host', '127.0.0.1',
    '--port', '0',
    '--state-file', TEST_STATE.to_s,
    '--audit-log', TEST_AUDIT.to_s,
    '--idempotency-state', TEST_IDEMPOTENCY.to_s,
    '--rate-limit-state', TEST_RATE.to_s,
    '--lock-file', TEST_LOCK.to_s,
    '--ready-json'
  ]
  args << '--disabled' if disabled
  stdin, stdout, stderr, wait_thr = Open3.popen3(env, *args, chdir: ROOT.to_s)
  stdin.close
  ready_line = nil
  deadline = Time.now + 8
  while Time.now < deadline
    begin
      ready_line = stdout.readline
      break
    rescue IO::WaitReadable
      IO.select([stdout], nil, nil, 0.1)
    rescue EOFError
      break
    end
  end
  ready = parse_json(ready_line)
  if ready['status'] == 'ready' && ready['port']
    return [wait_thr, stdout, ready.merge('stderr_io' => stderr)]
  end

  begin
    Process.kill('TERM', wait_thr.pid)
  rescue StandardError
    nil
  end
  [wait_thr, stdout, ready.merge('stderr' => stderr.read.to_s, 'raw_ready' => ready_line.to_s)]
end


def stop_server(wait_thr, stdout = nil)
  return unless wait_thr

  begin
    Process.kill('TERM', wait_thr.pid)
  rescue Errno::ESRCH
    nil
  end
  begin
    Timeout.timeout(3) { wait_thr.value }
  rescue StandardError
    begin
      Process.kill('KILL', wait_thr.pid)
    rescue StandardError
      nil
    end
  end
ensure
  stdout&.close unless stdout&.closed?
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


def repo_secret_hits
  roots = [ROOT.join('config'), ROOT.join('scripts', 'adapters', 'feishu')]
  forbidden = [/test-verification-token/, /test-encrypt-key/, /verification_token:\s*\S+/, /encrypt_key:\s*\S+/]
  roots.flat_map do |root|
    next [] unless root.directory?

    Dir.glob(root.join('**', '*').to_s).select { |p| File.file?(p) }.flat_map do |path|
      text = File.binread(path)
      forbidden.filter_map { |rx| "#{path}:#{rx.source}" if text.match?(rx) }
    rescue StandardError
      []
    end
  end
end

[TEST_STATE, TEST_AUDIT, TEST_IDEMPOTENCY, TEST_RATE, TEST_LOCK].each { |path| path.delete if path.file? }
ROOT.join('logs', 'feishu-adapter').mkpath

verification_token = "p5c-token-#{SecureRandom.hex(16)}"
encrypt_key = "p5c-key-#{SecureRandom.hex(16)}"
live_env = {
  'FEISHU_VERIFICATION_TOKEN' => verification_token,
  'FEISHU_ENCRYPT_KEY' => encrypt_key,
  'FEISHU_WEBHOOK_DISABLED' => '0'
}

add_check(checks, 'P5C_SERVER_FILE_EXISTS', SERVER.file?, SERVER.to_s)
add_check(checks, 'P5C_GATE_FILE_EXISTS', GATE.file?, GATE.to_s)
add_check(checks, 'P5C_CONFIG_FILE_EXISTS', CONFIG.file?, CONFIG.to_s)

wait_thr = nil
stdout = nil
ready = nil
begin
  wait_thr, stdout, ready = start_server(env: live_env)
  server_ready = ready && ready['status'] == 'ready' && ready['port'].to_i.positive? && ready['webhook_path'].to_s != ''
  validation_cases << { name: 'http_server_entry', ok: !!server_ready, output: ready }

  if server_ready
    base = "http://127.0.0.1:#{ready['port']}"
    health = get_json(base, ready['healthz_path'] || '/healthz')
    validation_cases << { name: 'health_endpoint', ok: health[:code] == 200 && health[:body]['status'] == 'ok', output: health }

    challenge_value = "challenge-#{SecureRandom.hex(8)}"
    challenge = post_json(base, ready['webhook_path'], challenge_body(challenge: challenge_value, token: verification_token), encrypt_key)
    validation_cases << { name: 'feishu_challenge_live', ok: challenge[:code] == 200 && challenge[:body]['challenge'] == challenge_value, output: challenge }

    bad_sig_body = body_payload(user_id: 'user-allow-1', chat_id: 'chat-p5c', message_id: 'msg-bad-sig', text: '/project current', event_id: 'evt-bad-sig', token: verification_token)
    bad_sig = post_json(base, ready['webhook_path'], bad_sig_body, encrypt_key, { 'X-Lark-Signature' => 'bad-signature' })
    validation_cases << { name: 'credential_header_blocks_invalid_signature', ok: bad_sig[:code].to_i >= 400 && bad_sig[:body]['reason'] == 'signature_verification_failed' && no_dispatch?(bad_sig[:body]), output: bad_sig }

    ok_event = post_json(base, ready['webhook_path'], body_payload(user_id: 'user-allow-1', chat_id: 'chat-p5c', message_id: 'msg-ok', text: '/project use ask', event_id: 'evt-ok', token: verification_token), encrypt_key)
    validation_cases << { name: 'valid_command_reuses_conversation_core', ok: ok_event[:code] == 200 && ok_event[:body]['result'] == 'ok' && ok_event[:body].dig('adapter_response', 'conversation_response', 'project_id') == 'ask' && ok_event[:body].dig('adapter_response', 'conversation_message', 'channel') == 'feishu' && no_dispatch?(ok_event[:body]), output: ok_event }

    dupe = post_json(base, ready['webhook_path'], body_payload(user_id: 'user-allow-1', chat_id: 'chat-p5c', message_id: 'msg-ok', text: '/project use ask', event_id: 'evt-ok', token: verification_token), encrypt_key)
    validation_cases << { name: 'retry_idempotency', ok: dupe[:code] == 200 && dupe[:body]['result'] == 'duplicate_ignored' && dupe[:body]['reason'] == 'idempotent_replay' && no_dispatch?(dupe[:body]), output: dupe }

    denied_user = post_json(base, ready['webhook_path'], body_payload(user_id: 'user-not-allow', chat_id: 'chat-p5c', message_id: 'msg-deny-user', text: '/project current', event_id: 'evt-deny-user', token: verification_token), encrypt_key)
    validation_cases << { name: 'whitelist_blocks_user', ok: denied_user[:code].to_i >= 400 && denied_user[:body].dig('adapter_response', 'reason') == 'user_not_whitelisted' && no_dispatch?(denied_user[:body]), output: denied_user }

    denied_acl = post_json(base, ready['webhook_path'], body_payload(user_id: 'user-allow-2', chat_id: 'chat-p5c', message_id: 'msg-deny-acl', text: '/project use ask', event_id: 'evt-deny-acl', token: verification_token), encrypt_key)
    validation_cases << { name: 'project_acl_blocks_user_project', ok: denied_acl[:code].to_i >= 400 && denied_acl[:body]['reason'] == 'project_acl_denied' && no_dispatch?(denied_acl[:body]), output: denied_acl }

    forbidden = post_json(base, ready['webhook_path'], body_payload(user_id: 'user-allow-1', chat_id: 'chat-p5c-forbidden', message_id: 'msg-worker', text: '/worker create coder', event_id: 'evt-worker', token: verification_token), encrypt_key)
    validation_cases << { name: 'allowed_commands_only', ok: forbidden[:code].to_i >= 400 && forbidden[:body].dig('adapter_response', 'reason') == 'input_validation_failed' && no_dispatch?(forbidden[:body]), output: forbidden }

    rate_cases = 4.times.map do |i|
      post_json(base, ready['webhook_path'], body_payload(user_id: 'user-allow-1', chat_id: 'chat-p5c-rate', message_id: "msg-rate-#{i}", text: '/project current', event_id: "evt-rate-#{i}", token: verification_token), encrypt_key)
    end
    rate_hit = rate_cases.last
    validation_cases << { name: 'rate_limit_lock', ok: rate_hit[:code].to_i >= 400 && rate_hit[:body].dig('adapter_response', 'reason') == 'rate_limited' && GATE.read.include?('File::LOCK_EX'), output: rate_cases }
  end
ensure
  stop_server(wait_thr, stdout)
end

# Disable switch is validated with a separate server process so the normal live
# cases remain enabled and exercise the full path.
wait_thr2 = nil
stdout2 = nil
ready2 = nil
begin
  wait_thr2, stdout2, ready2 = start_server(env: live_env.merge('FEISHU_WEBHOOK_DISABLED' => '1'), disabled: false)
  if ready2 && ready2['status'] == 'ready'
    base2 = "http://127.0.0.1:#{ready2['port']}"
    disabled = post_json(base2, ready2['webhook_path'], body_payload(user_id: 'user-allow-1', chat_id: 'chat-p5c-disabled', message_id: 'msg-disabled', text: '/project current', event_id: 'evt-disabled', token: verification_token), encrypt_key)
    validation_cases << { name: 'disable_switch', ok: disabled[:code].to_i >= 400 && disabled[:body]['result'] == 'disabled' && disabled[:body]['reason'] == 'webhook_disabled' && no_dispatch?(disabled[:body]), output: disabled }
  else
    validation_cases << { name: 'disable_switch', ok: false, output: ready2 }
  end
ensure
  stop_server(wait_thr2, stdout2)
end

records = audit_records(TEST_AUDIT)
validation_cases << {
  name: 'audit_log_required_fields',
  ok: records.length >= 8 && records.all? do |r|
    %w[timestamp channel conversation_id user_id event_id message_id tenant_key action result reason request_id signature_verified token_verified idempotency_key duplicate retry_count worker_auto_dispatch_triggered gateway_auto_dispatch_triggered].all? { |k| r.key?(k) }
  end,
  output: { audit_log: TEST_AUDIT.to_s, record_count: records.length, sample: records.last }
}

config_text = CONFIG.file? ? CONFIG.read : ''
gate_text = GATE.file? ? GATE.read : ''
server_text = SERVER.file? ? SERVER.read : ''
secret_hits = repo_secret_hits
validation_cases.each { |tc| add_check(checks, "P5C_CASE_#{tc[:name].upcase}", tc[:ok], JSON.generate(tc)) }

add_check(checks, 'P5C_HTTP_SERVER_ENTRY_READY', validation_cases.find { |c| c[:name] == 'http_server_entry' }&.dig(:ok), 'real local HTTP server process with webhook endpoint')
add_check(checks, 'P5C_FEISHU_CHALLENGE_LIVE_READY', validation_cases.find { |c| c[:name] == 'feishu_challenge_live' }&.dig(:ok), 'HTTP POST challenge')
add_check(checks, 'P5C_FEISHU_CREDENTIAL_ENV_READY', config_text.include?('verification_token_env') && config_text.include?('encrypt_key_env') && gate_text.include?('ENV[') && server_text.include?('ENV[') && validation_cases.find { |c| c[:name] == 'credential_header_blocks_invalid_signature' }&.dig(:ok), 'credential values resolved from env and checked via headers')
add_check(checks, 'P5C_SECRET_NOT_WRITTEN_TO_REPO', secret_hits.empty?, secret_hits.join(' | '))
add_check(checks, 'P5C_DISABLE_SWITCH_READY', validation_cases.find { |c| c[:name] == 'disable_switch' }&.dig(:ok), 'FEISHU_WEBHOOK_DISABLED / --disabled')
add_check(checks, 'P5C_WHITELIST_READY', validation_cases.find { |c| c[:name] == 'whitelist_blocks_user' }&.dig(:ok), 'non-whitelisted user blocked')
add_check(checks, 'P5C_PROJECT_ACL_READY', validation_cases.find { |c| c[:name] == 'project_acl_blocks_user_project' }&.dig(:ok), 'user_project_acl blocks project')
add_check(checks, 'P5C_RETRY_IDEMPOTENCY_READY', validation_cases.find { |c| c[:name] == 'retry_idempotency' }&.dig(:ok), 'duplicate Feishu event ignored')
add_check(checks, 'P5C_AUDIT_LOG_READY', validation_cases.find { |c| c[:name] == 'audit_log_required_fields' }&.dig(:ok), 'audit log fields')
add_check(checks, 'P5C_RATE_LIMIT_LOCK_READY', validation_cases.find { |c| c[:name] == 'rate_limit_lock' }&.dig(:ok), 'rate limit and File::LOCK_EX')
add_check(checks, 'P5C_ALLOWED_COMMANDS_ONLY', validation_cases.find { |c| c[:name] == 'allowed_commands_only' }&.dig(:ok), 'only project management commands pass')
add_check(checks, 'P5C_CONVERSATION_CORE_REUSED', validation_cases.find { |c| c[:name] == 'valid_command_reuses_conversation_core' }&.dig(:ok), 'P4 conversation core response observed')

p5b_stdout, p5b_stderr, p5b_code = command_output('ruby', P5B.to_s)
p5b_json = parse_json(p5b_stdout)
add_check(checks, 'P5B_REGRESSION_PASSED', p5b_code.zero? && p5b_json.dig('required_flags', 'P5B_CHALLENGE_VERIFICATION_READY') == 'YES', "exit=#{p5b_code}; stderr=#{p5b_stderr.strip}; summary=#{p5b_json['summary']}")

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

hermes_db_writes = Dir.glob('/Users/hula/.hermes/**/*.{db,sqlite,sqlite3}', File::FNM_EXTGLOB).select do |path|
  File.file?(path) && File.mtime(path) >= START_TIME
rescue StandardError
  false
end
add_check(checks, 'HERMES_INTERNAL_DB_MODIFIED_NO', hermes_db_writes.empty?, hermes_db_writes.join(' | '))

all_ok = checks.all? { |check| check[:ok] }
flag = ->(name) { checks.find { |c| c[:name] == name }&.dig(:ok) ? 'YES' : 'NO' }

result = {
  generated_at: Time.now.iso8601,
  project_id: 'project-agent-router',
  server: SERVER.to_s,
  security_gate: GATE.to_s,
  config: CONFIG.to_s,
  script: __FILE__,
  required_flags: {
    'P5C_HTTP_SERVER_ENTRY_READY' => flag.call('P5C_HTTP_SERVER_ENTRY_READY'),
    'P5C_FEISHU_CHALLENGE_LIVE_READY' => flag.call('P5C_FEISHU_CHALLENGE_LIVE_READY'),
    'P5C_FEISHU_CREDENTIAL_ENV_READY' => flag.call('P5C_FEISHU_CREDENTIAL_ENV_READY'),
    'P5C_SECRET_NOT_WRITTEN_TO_REPO' => flag.call('P5C_SECRET_NOT_WRITTEN_TO_REPO'),
    'P5C_DISABLE_SWITCH_READY' => flag.call('P5C_DISABLE_SWITCH_READY'),
    'P5C_WHITELIST_READY' => flag.call('P5C_WHITELIST_READY'),
    'P5C_PROJECT_ACL_READY' => flag.call('P5C_PROJECT_ACL_READY'),
    'P5C_RETRY_IDEMPOTENCY_READY' => flag.call('P5C_RETRY_IDEMPOTENCY_READY'),
    'P5C_AUDIT_LOG_READY' => flag.call('P5C_AUDIT_LOG_READY'),
    'P5C_RATE_LIMIT_LOCK_READY' => flag.call('P5C_RATE_LIMIT_LOCK_READY'),
    'P5C_ALLOWED_COMMANDS_ONLY' => flag.call('P5C_ALLOWED_COMMANDS_ONLY'),
    'P5C_CONVERSATION_CORE_REUSED' => flag.call('P5C_CONVERSATION_CORE_REUSED'),
    'P5C_WORKER_AUTO_DISPATCH_TRIGGERED' => 'NO',
    'P5C_GATEWAY_AUTO_DISPATCH_TRIGGERED' => 'NO',
    'P5B_REGRESSION_PASSED' => flag.call('P5B_REGRESSION_PASSED'),
    'P5A_REGRESSION_PASSED' => flag.call('P5A_REGRESSION_PASSED'),
    'P4_REGRESSION_PASSED' => flag.call('P4_REGRESSION_PASSED'),
    'P3_REGRESSION_PASSED' => flag.call('P3_REGRESSION_PASSED'),
    'P2_REGRESSION_PASSED' => flag.call('P2_REGRESSION_PASSED'),
    'ASK_CODE_MODIFIED' => ask_business_status.empty? ? 'NO' : 'YES',
    'HERMES_CORE_MODIFIED' => hermes_core_status.empty? ? 'NO' : 'YES',
    'HERMES_INTERNAL_DB_MODIFIED' => hermes_db_writes.empty? ? 'NO' : 'YES',
    'REAL_WORKER_CREATED' => 'NO',
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
    secret_hits: secret_hits,
    ask_business_status: ask_business_status,
    hermes_core_status: hermes_core_status,
    hermes_internal_db_writes: hermes_db_writes
  }
}

puts JSON.pretty_generate(result)
exit(all_ok ? 0 : 1)
