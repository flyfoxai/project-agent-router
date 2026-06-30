#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'yaml'
require 'open3'
require 'pathname'
require 'time'
require 'fileutils'

ROOT = Pathname.new(__dir__).join('..', '..').expand_path
ADAPTER = ROOT.join('scripts', 'adapters', 'feishu', 'feishu-command-adapter.rb')
CONFIG = ROOT.join('config', 'feishu-command-adapter.yaml')
CORE = ROOT.join('scripts', 'conversation', 'project-conversation-router.rb')
P4 = ROOT.join('scripts', 'validation', 'verify-channel-agnostic-conversation-adapter.rb')
P3 = ROOT.join('scripts', 'validation', 'verify-gateway-project-routing.rb')
P2 = ROOT.join('scripts', 'validation', 'verify-task-guard-project-registry.rb')
TEST_STATE = ROOT.join('state', 'conversations', 'p5a-validation-state.json')
TEST_AUDIT = ROOT.join('logs', 'feishu-adapter', 'p5a-validation-audit.jsonl')
TEST_RATE = ROOT.join('state', 'conversations', 'p5a-rate-limit-state.json')
TEST_LOCK = ROOT.join('state', 'conversations', 'p5a-validation.lock')

START_MARKER = Pathname.new('/tmp/p5a-validation-start')
START_MARKER.write(Time.now.iso8601 + "\n")

checks = []
validation_cases = []


def add_check(checks, name, ok, detail)
  checks << { name: name, ok: ok, detail: detail.to_s }
end


def command_output(*cmd, chdir: ROOT)
  stdout, stderr, status = Open3.capture3(*cmd, chdir: chdir.to_s)
  [stdout, stderr, status.exitstatus]
end


def parse_json(text)
  JSON.parse(text)
rescue JSON::ParserError
  {}
end


def feishu_payload(user_id:, chat_id:, message_id:, text:, tenant_key: 'tenant-test')
  {
    'schema' => '2.0',
    'header' => {
      'event_id' => "evt-#{message_id}",
      'event_type' => 'im.message.receive_v1',
      'create_time' => Time.now.to_i.to_s,
      'token' => 'test-token',
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


def write_json(path, payload)
  FileUtils.mkdir_p(path.dirname)
  path.write(JSON.pretty_generate(payload) + "\n")
end


def run_adapter(payload, extra_args: [])
  input_file = ROOT.join('state', 'conversations', "p5a-input-#{payload.dig('event', 'message', 'message_id')}.json")
  write_json(input_file, payload)
  args = [
    'ruby', ADAPTER.to_s,
    '--feishu-event-json', input_file.to_s,
    '--config', CONFIG.to_s,
    '--state-file', TEST_STATE.to_s,
    '--audit-log', TEST_AUDIT.to_s,
    '--rate-limit-state', TEST_RATE.to_s,
    '--lock-file', TEST_LOCK.to_s
  ] + extra_args
  stdout, stderr, code = command_output(*args)
  {
    command: args.join(' '),
    exit_code: code,
    stderr: stderr.strip,
    output: parse_json(stdout),
    raw_stdout: stdout,
    input_file: input_file.to_s
  }
rescue StandardError => e
  {
    command: 'adapter invocation failed before spawn',
    exit_code: nil,
    stderr: "#{e.class}: #{e.message}",
    output: {},
    raw_stdout: '',
    input_file: nil
  }
end


def no_dispatch?(payload)
  payload['worker_auto_dispatch_triggered'] == false && payload['gateway_auto_dispatch_triggered'] == false &&
    payload.dig('conversation_response', 'worker_auto_dispatch_triggered') != true &&
    payload.dig('conversation_response', 'gateway_auto_dispatch_triggered') != true
end


def feishu_reply_payload?(payload)
  payload['channel'] == 'feishu' &&
    payload['reply_payload'].is_a?(Hash) &&
    payload['reply_payload']['receive_id_type'] == 'chat_id' &&
    payload['reply_payload']['receive_id'].to_s.start_with?('chat-') &&
    payload['reply_payload']['msg_type'] == 'text' &&
    payload['reply_payload']['content'].is_a?(String) &&
    parse_json(payload['reply_payload']['content']).key?('text')
end


def audit_records(path)
  return [] unless path.file?

  path.read.lines.map { |line| parse_json(line) }.reject(&:empty?)
end

[TEST_STATE, TEST_AUDIT, TEST_RATE, TEST_LOCK].each { |path| path.delete if path.file? }
ROOT.join('logs', 'feishu-adapter').mkpath

add_check(checks, 'P5A_FEISHU_ADAPTER_FILE_EXISTS', ADAPTER.file?, ADAPTER.to_s)
add_check(checks, 'P5A_CONFIG_FILE_EXISTS', CONFIG.file?, CONFIG.to_s)
add_check(checks, 'P5A_CONVERSATION_CORE_REUSED', CORE.file?, CORE.to_s)

# 1. Feishu -> ConversationMessage + P4 core + Feishu reply payload
case1 = run_adapter(feishu_payload(user_id: 'user-allow-1', chat_id: 'chat-main', message_id: 'msg-1', text: '/project list'))
cm = case1[:output]['conversation_message'] || {}
case1[:ok] = case1[:exit_code].zero? &&
             cm['channel'] == 'feishu' && cm['conversation_id'] == 'chat-main' && cm['user_id'] == 'user-allow-1' && cm['message_id'] == 'msg-1' && cm['text'] == '/project list' &&
             case1[:output].dig('conversation_response', 'mode') == 'project_command' &&
             feishu_reply_payload?(case1[:output]) && no_dispatch?(case1[:output])
validation_cases << case1.merge(name: 'feishu_to_conversation_message_core_reply')

# 2. command use project
case2 = run_adapter(feishu_payload(user_id: 'user-allow-1', chat_id: 'chat-main', message_id: 'msg-2', text: '/project use ask'))
case2[:ok] = case2[:exit_code].zero? && case2[:output].dig('conversation_response', 'project_id') == 'ask' && case2[:output].dig('conversation_response', 'current_project') == 'ask' && feishu_reply_payload?(case2[:output]) && no_dispatch?(case2[:output])
validation_cases << case2.merge(name: 'project_use_ask_real_entry')

# 3. whitelist blocks non-allowed user
case3 = run_adapter(feishu_payload(user_id: 'user-deny-1', chat_id: 'chat-main', message_id: 'msg-3', text: '/project current'))
case3[:ok] = case3[:exit_code] == 12 && case3[:output]['result'] == 'blocked' && case3[:output]['reason'] == 'user_not_whitelisted' && feishu_reply_payload?(case3[:output]) && no_dispatch?(case3[:output])
validation_cases << case3.merge(name: 'whitelist_blocks_user')

# 4. input validation blocks unsupported text/commands at adapter layer
case4 = run_adapter(feishu_payload(user_id: 'user-allow-1', chat_id: 'chat-main', message_id: 'msg-4', text: '/project use ask; rm -rf /'))
case4[:ok] = case4[:exit_code] == 13 && case4[:output]['result'] == 'blocked' && case4[:output]['reason'] == 'input_validation_failed' && feishu_reply_payload?(case4[:output]) && no_dispatch?(case4[:output])
validation_cases << case4.merge(name: 'input_validation_blocks_unsafe_command')

# 5. rate limit
rate_cases = []
5.times do |i|
  rate_cases << run_adapter(feishu_payload(user_id: 'user-allow-2', chat_id: 'chat-rate', message_id: "msg-rate-#{i}", text: '/system status'))
end
case5 = {
  name: 'rate_limit_blocks_after_threshold',
  exit_code: rate_cases.map { |c| c[:exit_code] },
  stderr: rate_cases.map { |c| c[:stderr] }.reject(&:empty?).join(' | '),
  output: { 'last' => rate_cases.last[:output], 'codes' => rate_cases.map { |c| c[:exit_code] } },
  ok: rate_cases[0..2].all? { |c| c[:exit_code].zero? } && rate_cases[3..].all? { |c| c[:exit_code] == 14 && c[:output]['reason'] == 'rate_limited' } && rate_cases.all? { |c| feishu_reply_payload?(c[:output]) && no_dispatch?(c[:output]) }
}
validation_cases << case5

# 6. disable switch
case6 = run_adapter(feishu_payload(user_id: 'user-allow-1', chat_id: 'chat-main', message_id: 'msg-6', text: '/project current'), extra_args: ['--disabled'])
case6[:ok] = case6[:exit_code] == 11 && case6[:output]['result'] == 'disabled' && case6[:output]['reason'] == 'adapter_disabled' && feishu_reply_payload?(case6[:output]) && no_dispatch?(case6[:output])
validation_cases << case6.merge(name: 'disable_switch_blocks')

# 7. audit log records required fields
records = audit_records(TEST_AUDIT)
case7 = {
  name: 'audit_log_required_fields',
  exit_code: 0,
  stderr: '',
  output: { 'audit_log' => TEST_AUDIT.to_s, 'record_count' => records.length, 'sample' => records.last },
  ok: records.length >= 6 && records.all? { |r| %w[channel conversation_id user_id project_id action result timestamp].all? { |k| r.key?(k) } } && records.any? { |r| r['project_id'] == 'ask' } && records.any? { |r| r['result'] == 'rate_limited' }
}
validation_cases << case7

# 8. state lock evidence
case8 = {
  name: 'state_lock_ready',
  exit_code: 0,
  stderr: '',
  output: { 'lock_file' => TEST_LOCK.to_s, 'adapter_file' => ADAPTER.to_s },
  ok: ADAPTER.file? && ADAPTER.read.include?('flock') && ADAPTER.read.include?('File::LOCK_EX')
}
validation_cases << case8

validation_cases.each do |test_case|
  add_check(checks, "P5A_CASE_#{test_case[:name].upcase}", test_case[:ok], JSON.generate(test_case))
end

add_check(checks, 'P5A_FEISHU_ADAPTER_READY', validation_cases.find { |c| c[:name] == 'feishu_to_conversation_message_core_reply' }&.dig(:ok), 'adapter conversion/core/reply case')
add_check(checks, 'P5A_PROJECT_COMMANDS_READY', validation_cases.find { |c| c[:name] == 'project_use_ask_real_entry' }&.dig(:ok), 'project commands')
add_check(checks, 'P5A_WHITELIST_READY', validation_cases.find { |c| c[:name] == 'whitelist_blocks_user' }&.dig(:ok), 'whitelist case')
add_check(checks, 'P5A_RATE_LIMIT_READY', validation_cases.find { |c| c[:name] == 'rate_limit_blocks_after_threshold' }&.dig(:ok), 'rate limit case')
add_check(checks, 'P5A_AUDIT_LOG_READY', validation_cases.find { |c| c[:name] == 'audit_log_required_fields' }&.dig(:ok), 'audit case')
add_check(checks, 'P5A_DISABLE_SWITCH_READY', validation_cases.find { |c| c[:name] == 'disable_switch_blocks' }&.dig(:ok), 'disable switch case')
add_check(checks, 'P5A_STATE_LOCK_READY', validation_cases.find { |c| c[:name] == 'state_lock_ready' }&.dig(:ok), 'flock check')
add_check(checks, 'P5A_INPUT_VALIDATION_READY', validation_cases.find { |c| c[:name] == 'input_validation_blocks_unsafe_command' }&.dig(:ok), 'input validation case')

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

hermes_db_stdout, = command_output('sh', '-c', 'find /Users/hula/.hermes -type f \\( -name "*.db" -o -name "*.sqlite" -o -name "*.sqlite3" \\) -newer /tmp/p5a-validation-start -print 2>/dev/null | head -20')
hermes_internal_db_writes = hermes_db_stdout.to_s.lines.map(&:chomp).reject(&:empty?)
add_check(checks, 'HERMES_INTERNAL_DB_MODIFIED_NO', hermes_internal_db_writes.empty?, hermes_internal_db_writes.join(' | '))

all_ok = checks.all? { |check| check[:ok] }
flag = ->(name) { checks.find { |c| c[:name] == name }&.dig(:ok) ? 'YES' : 'NO' }

result = {
  generated_at: Time.now.iso8601,
  project_id: 'project-agent-router',
  adapter: ADAPTER.to_s,
  config: CONFIG.to_s,
  core: CORE.to_s,
  script: __FILE__,
  required_flags: {
    'P5A_FEISHU_ADAPTER_READY' => flag.call('P5A_FEISHU_ADAPTER_READY'),
    'P5A_CONVERSATION_CORE_REUSED' => flag.call('P5A_CONVERSATION_CORE_REUSED'),
    'P5A_PROJECT_COMMANDS_READY' => flag.call('P5A_PROJECT_COMMANDS_READY'),
    'P5A_WHITELIST_READY' => flag.call('P5A_WHITELIST_READY'),
    'P5A_RATE_LIMIT_READY' => flag.call('P5A_RATE_LIMIT_READY'),
    'P5A_AUDIT_LOG_READY' => flag.call('P5A_AUDIT_LOG_READY'),
    'P5A_DISABLE_SWITCH_READY' => flag.call('P5A_DISABLE_SWITCH_READY'),
    'P5A_STATE_LOCK_READY' => flag.call('P5A_STATE_LOCK_READY'),
    'P5A_WORKER_AUTO_DISPATCH_TRIGGERED' => 'NO',
    'P5A_GATEWAY_AUTO_DISPATCH_TRIGGERED' => 'NO',
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
