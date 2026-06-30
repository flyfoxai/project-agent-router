#!/usr/bin/env ruby
# frozen_string_literal: true

require 'yaml'
require 'json'
require 'open3'
require 'pathname'
require 'tmpdir'
require 'time'

ROOT = Pathname.new(__dir__).join('..', '..').expand_path
REGISTRY = ROOT.join('config', 'projects.yaml')
TEMPLATE = ROOT.join('templates', 'channel-agnostic-conversation-adapter.md')
SAMPLE_STATE = ROOT.join('state', 'conversations', 'sample-state.json')
CORE = ROOT.join('scripts', 'conversation', 'project-conversation-router.rb')
P3 = ROOT.join('scripts', 'validation', 'verify-gateway-project-routing.rb')
P2 = ROOT.join('scripts', 'validation', 'verify-task-guard-project-registry.rb')
REQUIRED_PROJECTS = %w[ask multiagent-orchestration-system].freeze

checks = []
validation_cases = []


def add_check(checks, name, ok, detail)
  checks << { name: name, ok: ok, detail: detail.to_s }
end


def command_output(*cmd, chdir: ROOT)
  stdout, stderr, status = Open3.capture3(*cmd, chdir: chdir.to_s)
  [stdout, stderr, status.exitstatus]
end


def parse_json(stdout)
  JSON.parse(stdout)
rescue JSON::ParserError
  {}
end


def conversation_message(channel:, conversation_id:, user_id:, message_id:, text:)
  {
    'channel' => channel,
    'conversation_id' => conversation_id,
    'user_id' => user_id,
    'message_id' => message_id,
    'text' => text,
    'timestamp' => Time.now.iso8601,
    'metadata' => { 'raw_platform' => channel }
  }
end


def run_core(message, state_file)
  stdout, stderr, code = command_output('ruby', CORE.to_s, '--message-json', JSON.generate(message), '--state-file', state_file.to_s)
  {
    name: message['text'],
    command: "ruby #{CORE} --message-json <json> --state-file #{state_file}",
    exit_code: code,
    stderr: stderr.strip,
    output: parse_json(stdout),
    raw_stdout: stdout
  }
rescue StandardError => e
  {
    name: message['text'],
    command: "ruby #{CORE} --message-json <json> --state-file #{state_file}",
    exit_code: nil,
    stderr: "#{e.class}: #{e.message}",
    output: {},
    raw_stdout: ''
  }
end


def common_no_dispatch?(payload)
  payload['worker_auto_dispatch_triggered'] == false &&
    payload['gateway_auto_dispatch_triggered'] == false &&
    payload.dig('dry_run_work_order', 'dispatch', 'worker_auto_dispatch_triggered') != true &&
    payload.dig('dry_run_work_order', 'dispatch', 'gateway_auto_dispatch_triggered') != true
end


def response_schema_ready?(payload)
  required = %w[
    mode project_id project_display_name routing_source routing_confidence
    requires_clarification response_text reporter_header project_label board
    workspace_path git_root git_root_status dispatch_mode actions
    dry_run_work_order worker_auto_dispatch_triggered gateway_auto_dispatch_triggered
  ]
  required.all? { |key| payload.key?(key) } &&
    payload['actions'].is_a?(Hash) &&
    payload['actions'].key?('update_current_project') &&
    payload['actions'].key?('update_default_project')
end

registry = nil
begin
  registry = YAML.safe_load(REGISTRY.read, aliases: false)
  add_check(checks, 'P4_REGISTRY_PARSE_READY', registry.is_a?(Hash), 'config/projects.yaml parsed')
rescue StandardError => e
  add_check(checks, 'P4_REGISTRY_PARSE_READY', false, "#{e.class}: #{e.message}")
end
projects = registry&.fetch('projects', {}) || {}
add_check(checks, 'P4_PROJECTS_PRESENT', (REQUIRED_PROJECTS - projects.keys).empty?, projects.keys.sort.join(','))
add_check(checks, 'P4_CONVERSATION_MESSAGE_SCHEMA_READY', TEMPLATE.file? && %w[channel conversation_id user_id message_id text timestamp metadata raw_platform].all? { |s| TEMPLATE.read.include?(s) }, TEMPLATE.to_s)
add_check(checks, 'P4_CONVERSATION_RESPONSE_SCHEMA_READY', TEMPLATE.file? && %w[mode project_id project_display_name routing_source routing_confidence requires_clarification response_text reporter_header project_label board workspace_path git_root git_root_status dispatch_mode actions update_current_project update_default_project dry_run_work_order].all? { |s| TEMPLATE.read.include?(s) }, TEMPLATE.to_s)
add_check(checks, 'P4_STATE_STORE_SCHEMA_READY', SAMPLE_STATE.file? && %w[version conversations current_project default_project updated_at last_routing_source last_message_id].all? { |s| SAMPLE_STATE.read.include?(s) }, SAMPLE_STATE.to_s)
add_check(checks, 'P4_CORE_SCRIPT_EXISTS', CORE.file?, CORE.to_s)

state_file = ROOT.join('state', 'conversations', 'p4-validation-state.json')
state_file.delete if state_file.file?
begin
  # 1. 当前一共有几个项目？
  c1 = run_core(conversation_message(channel: 'feishu', conversation_id: 'conv-a', user_id: 'user-1', message_id: 'm1', text: '当前一共有几个项目？'), state_file)
  c1[:ok] = c1[:exit_code].zero? && c1[:output]['mode'] == 'project_command' && c1[:output]['projects'].is_a?(Array) && c1[:output]['projects'].map { |p| p['project_id'] }.sort == REQUIRED_PROJECTS.sort && common_no_dispatch?(c1[:output]) && response_schema_ready?(c1[:output])
  validation_cases << c1.merge(name: 'project_list_natural_language')

  # 2. 当前项目是什么？ empty
  c2 = run_core(conversation_message(channel: 'feishu', conversation_id: 'conv-a', user_id: 'user-1', message_id: 'm2', text: '当前项目是什么？'), state_file)
  c2[:ok] = c2[:exit_code].zero? && c2[:output]['mode'] == 'project_command' && c2[:output]['current_project'].nil? && c2[:output]['default_project'].nil? && c2[:output]['response_text'].include?('当前项目未设置') && common_no_dispatch?(c2[:output]) && response_schema_ready?(c2[:output])
  validation_cases << c2.merge(name: 'current_project_empty')

  # 3. 切到 ASK
  c3 = run_core(conversation_message(channel: 'feishu', conversation_id: 'conv-a', user_id: 'user-1', message_id: 'm3', text: '切到 ASK'), state_file)
  c3[:ok] = c3[:exit_code].zero? && c3[:output]['mode'] == 'project_command' && c3[:output]['project_id'] == 'ask' && c3[:output].dig('actions', 'update_current_project') == 'ask' && common_no_dispatch?(c3[:output]) && response_schema_ready?(c3[:output])
  validation_cases << c3.merge(name: 'use_ask_natural_language')

  # 4. /project use multiagent-orchestration-system
  c4 = run_core(conversation_message(channel: 'feishu', conversation_id: 'conv-a', user_id: 'user-1', message_id: 'm4', text: '/project use multiagent-orchestration-system'), state_file)
  c4[:ok] = c4[:exit_code].zero? && c4[:output]['project_id'] == 'multiagent-orchestration-system' && c4[:output].dig('actions', 'update_current_project') == 'multiagent-orchestration-system' && common_no_dispatch?(c4[:output]) && response_schema_ready?(c4[:output])
  validation_cases << c4.merge(name: 'project_use_multiagent_command')

  # 5. 我下面说的话对哪个项目有效？
  c5 = run_core(conversation_message(channel: 'feishu', conversation_id: 'conv-a', user_id: 'user-1', message_id: 'm5', text: '我下面说的话对哪个项目有效？'), state_file)
  c5[:ok] = c5[:exit_code].zero? && c5[:output]['current_project'] == 'multiagent-orchestration-system' && c5[:output]['response_text'].include?('优先级') && c5[:output]['response_text'].include?('显式项目') && common_no_dispatch?(c5[:output]) && response_schema_ready?(c5[:output])
  validation_cases << c5.merge(name: 'routing_scope_explanation')

  # 6. /project clear
  c6 = run_core(conversation_message(channel: 'feishu', conversation_id: 'conv-a', user_id: 'user-1', message_id: 'm6', text: '/project clear'), state_file)
  c6[:ok] = c6[:exit_code].zero? && c6[:output]['current_project'].nil? && c6[:output].dig('actions', 'update_current_project').nil? && common_no_dispatch?(c6[:output]) && response_schema_ready?(c6[:output])
  validation_cases << c6.merge(name: 'project_clear')

  # 7. /project default ask
  c7 = run_core(conversation_message(channel: 'feishu', conversation_id: 'conv-a', user_id: 'user-1', message_id: 'm7', text: '/project default ask'), state_file)
  c7[:ok] = c7[:exit_code].zero? && c7[:output]['default_project'] == 'ask' && c7[:output]['current_project'].nil? && c7[:output].dig('actions', 'update_default_project') == 'ask' && common_no_dispatch?(c7[:output]) && response_schema_ready?(c7[:output])
  validation_cases << c7.merge(name: 'project_default_ask')

  # 8. 只做通用分析，不进入项目
  c8 = run_core(conversation_message(channel: 'feishu', conversation_id: 'conv-a', user_id: 'user-1', message_id: 'm8', text: '只做通用分析，不进入项目'), state_file)
  c8[:ok] = c8[:exit_code].zero? && c8[:output]['mode'] == 'ask' && c8[:output]['project_id'].nil? && common_no_dispatch?(c8[:output]) && response_schema_ready?(c8[:output])
  validation_cases << c8.merge(name: 'ask_mode_no_project')

  # 9. /orchestration status
  c9 = run_core(conversation_message(channel: 'feishu', conversation_id: 'conv-a', user_id: 'user-1', message_id: 'm9', text: '/orchestration status'), state_file)
  c9[:ok] = c9[:exit_code].zero? && c9[:output]['mode'] == 'system_meta' && c9[:output]['project_id'].nil? && common_no_dispatch?(c9[:output]) && response_schema_ready?(c9[:output])
  validation_cases << c9.merge(name: 'orchestration_status_system_meta')

  # 10. 继续做 low confidence
  c10 = run_core(conversation_message(channel: 'feishu', conversation_id: 'conv-c', user_id: 'user-1', message_id: 'm10', text: '继续做'), state_file)
  c10[:ok] = c10[:exit_code] == 10 && c10[:output]['mode'] == 'blocked' && c10[:output]['project_id'] == 'blocked' && c10[:output]['requires_clarification'] == true && common_no_dispatch?(c10[:output]) && response_schema_ready?(c10[:output])
  validation_cases << c10.merge(name: 'low_confidence_block')

  # 11. channel isolation
  a1 = run_core(conversation_message(channel: 'feishu', conversation_id: 'conv-isolated', user_id: 'same-user', message_id: 'ma1', text: '/project use ask'), state_file)
  b1 = run_core(conversation_message(channel: 'slack', conversation_id: 'conv-isolated', user_id: 'same-user', message_id: 'mb1', text: '/project use multiagent-orchestration-system'), state_file)
  a2 = run_core(conversation_message(channel: 'feishu', conversation_id: 'conv-isolated', user_id: 'same-user', message_id: 'ma2', text: '/project current'), state_file)
  b2 = run_core(conversation_message(channel: 'slack', conversation_id: 'conv-isolated', user_id: 'same-user', message_id: 'mb2', text: '/project current'), state_file)
  c11 = {
    name: 'channel_isolation',
    command: 'feishu/slack isolated state sequence',
    exit_code: [a1[:exit_code], b1[:exit_code], a2[:exit_code], b2[:exit_code]],
    stderr: [a1[:stderr], b1[:stderr], a2[:stderr], b2[:stderr]].reject(&:empty?).join(' | '),
    output: { 'feishu_current' => a2[:output]['current_project'], 'slack_current' => b2[:output]['current_project'], 'state_file' => state_file.to_s },
    ok: a2[:output]['current_project'] == 'ask' && b2[:output]['current_project'] == 'multiagent-orchestration-system' && common_no_dispatch?(a1[:output]) && common_no_dispatch?(b1[:output]) && common_no_dispatch?(a2[:output]) && common_no_dispatch?(b2[:output])
  }
  validation_cases << c11

  state_payload = state_file.file? ? JSON.parse(state_file.read) : {}
  keys = state_payload.fetch('conversations', {}).keys
  add_check(checks, 'P4_CHANNEL_ISOLATION_READY', c11[:ok] && keys.any? { |k| k.start_with?('feishu:conv-isolated:same-user') } && keys.any? { |k| k.start_with?('slack:conv-isolated:same-user') }, keys.join(','))
end

validation_cases.each do |test_case|
  add_check(checks, "P4_CASE_#{test_case[:name].upcase}", test_case[:ok], JSON.generate(test_case))
end

add_check(checks, 'P4_PROJECT_LIST_READY', validation_cases.find { |c| c[:name] == 'project_list_natural_language' }&.dig(:ok), 'project list case')
add_check(checks, 'P4_CURRENT_PROJECT_READY', validation_cases.find { |c| c[:name] == 'current_project_empty' }&.dig(:ok), 'current project case')
add_check(checks, 'P4_PROJECT_USE_READY', validation_cases.find { |c| c[:name] == 'use_ask_natural_language' }&.dig(:ok) && validation_cases.find { |c| c[:name] == 'project_use_multiagent_command' }&.dig(:ok), 'project use cases')
add_check(checks, 'P4_PROJECT_CLEAR_READY', validation_cases.find { |c| c[:name] == 'project_clear' }&.dig(:ok), 'project clear case')
add_check(checks, 'P4_DEFAULT_PROJECT_READY', validation_cases.find { |c| c[:name] == 'project_default_ask' }&.dig(:ok), 'project default case')
add_check(checks, 'P4_SYSTEM_META_READY', validation_cases.find { |c| c[:name] == 'orchestration_status_system_meta' }&.dig(:ok), 'system meta case')
add_check(checks, 'P4_LOW_CONFIDENCE_BLOCK_READY', validation_cases.find { |c| c[:name] == 'low_confidence_block' }&.dig(:ok), 'low confidence case')

# Regressions
p3_stdout, p3_stderr, p3_code = command_output('ruby', P3.to_s)
p3_json = parse_json(p3_stdout)
add_check(checks, 'P3_REGRESSION_PASSED', p3_code.zero? && p3_json.dig('required_flags', 'P3_VALIDATION_PASSED') == 'YES', "exit=#{p3_code}; stderr=#{p3_stderr.strip}; summary=#{p3_json['summary']}")

p2_stdout, p2_stderr, p2_code = command_output('ruby', P2.to_s)
p2_json = parse_json(p2_stdout)
add_check(checks, 'P2_REGRESSION_PASSED', p2_code.zero? && p2_json.dig('summary', 'failed').to_i == 0, "exit=#{p2_code}; stderr=#{p2_stderr.strip}; summary=#{p2_json['summary']}")

ask_stdout, _ask_stderr, = command_output('git', '-C', '/Users/hula/workspace', 'status', '--short', '--', 'ASK/src', 'ASK/tests', 'ASK/packages', 'ASK/.git')
ask_business_status = ask_stdout.lines.map(&:chomp).reject(&:empty?)
add_check(checks, 'ASK_CODE_MODIFIED_NO', ask_business_status.empty?, ask_business_status.join(' | '))

hermes_stdout, _hermes_stderr, = command_output('git', '-C', '/Users/hula/workspace', 'status', '--short', '--', '/Users/hula/.hermes')
hermes_core_status = hermes_stdout.lines.map(&:chomp).reject(&:empty?)
add_check(checks, 'HERMES_CORE_MODIFIED_NO', hermes_core_status.empty?, hermes_core_status.join(' | '))

home_state_stdout, _home_state_stderr, = command_output('sh', '-c', 'find /Users/hula/.hermes -path "*/conversations/*" -type f -newer /tmp/p4-validation-start 2>/dev/null | head -20') if File.exist?('/tmp/p4-validation-start')
hermes_internal_db_writes = home_state_stdout.to_s.lines.map(&:chomp).reject(&:empty?)
add_check(checks, 'HERMES_INTERNAL_DB_MODIFIED_NO', hermes_internal_db_writes.empty?, hermes_internal_db_writes.join(' | '))

core_ready = checks.select { |c| c[:name].start_with?('P4_') && !c[:name].include?('CASE_') }.all? { |c| c[:ok] }
all_ok = checks.all? { |c| c[:ok] }
flag = ->(name) { checks.find { |c| c[:name] == name }&.dig(:ok) ? 'YES' : 'NO' }

result = {
  generated_at: Time.now.iso8601,
  project_id: 'multiagent-orchestration-system',
  registry: REGISTRY.to_s,
  template: TEMPLATE.to_s,
  sample_state: SAMPLE_STATE.to_s,
  core: CORE.to_s,
  script: __FILE__,
  required_flags: {
    'P4_CHANNEL_AGNOSTIC_CORE_READY' => core_ready ? 'YES' : 'NO',
    'P4_FEISHU_ADAPTER_DRY_RUN_READY' => flag.call('P4_CASE_USE_ASK_NATURAL_LANGUAGE'),
    'P4_SLACK_WECHAT_DISCORD_FUTURE_ADAPTER_READY' => flag.call('P4_CHANNEL_ISOLATION_READY'),
    'P4_CONVERSATION_MESSAGE_SCHEMA_READY' => flag.call('P4_CONVERSATION_MESSAGE_SCHEMA_READY'),
    'P4_CONVERSATION_RESPONSE_SCHEMA_READY' => flag.call('P4_CONVERSATION_RESPONSE_SCHEMA_READY'),
    'P4_STATE_STORE_SCHEMA_READY' => flag.call('P4_STATE_STORE_SCHEMA_READY'),
    'P4_CURRENT_PROJECT_READY' => flag.call('P4_CURRENT_PROJECT_READY'),
    'P4_DEFAULT_PROJECT_READY' => flag.call('P4_DEFAULT_PROJECT_READY'),
    'P4_PROJECT_LIST_READY' => flag.call('P4_PROJECT_LIST_READY'),
    'P4_PROJECT_USE_READY' => flag.call('P4_PROJECT_USE_READY'),
    'P4_PROJECT_CLEAR_READY' => flag.call('P4_PROJECT_CLEAR_READY'),
    'P4_SYSTEM_META_READY' => flag.call('P4_SYSTEM_META_READY'),
    'P4_LOW_CONFIDENCE_BLOCK_READY' => flag.call('P4_LOW_CONFIDENCE_BLOCK_READY'),
    'P4_CHANNEL_ISOLATION_READY' => flag.call('P4_CHANNEL_ISOLATION_READY'),
    'P4_VALIDATION_PASSED' => all_ok ? 'YES' : 'NO',
    'P3_REGRESSION_PASSED' => flag.call('P3_REGRESSION_PASSED'),
    'P2_REGRESSION_PASSED' => flag.call('P2_REGRESSION_PASSED'),
    'WORKER_AUTO_DISPATCH_TRIGGERED' => 'NO',
    'GATEWAY_AUTO_DISPATCH_TRIGGERED' => 'NO',
    'ASK_GIT_ROOT_MIGRATION_EXECUTED' => 'NO',
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
    ask_business_status: ask_business_status,
    hermes_core_status: hermes_core_status,
    hermes_internal_db_writes: hermes_internal_db_writes
  }
}

puts JSON.pretty_generate(result)
exit(all_ok ? 0 : 1)
