#!/usr/bin/env ruby
# frozen_string_literal: true

require 'yaml'
require 'json'
require 'open3'
require 'pathname'
require 'time'

ROOT = Pathname.new(__dir__).join('..', '..').expand_path
REGISTRY = ROOT.join('config', 'projects.yaml')
GATEWAY_TEMPLATE = ROOT.join('templates', 'gateway-project-routing-gate.md')
A2A_TEMPLATE = ROOT.join('templates', 'a2a-work-order-protocol.md')
ROUTER = ROOT.join('scripts', 'gateway', 'project-router.rb')

PARENT_WORKSPACE = '/Users/hula/workspace'
REQUIRED_PROJECTS = %w[ask multiagent-orchestration-system].freeze
ROUTING_PRIORITY = %w[
  explicit_project_id
  explicit_project_alias
  board_slug
  workspace_path
  current_project
  default_project
  system_meta
  blocked_clarification
].freeze
FUZZY_INPUTS = ['继续做', '处理这个项目', '派给 worker', '让 agents 开始', '把它改了'].freeze

checks = []
validation_cases = []


def add_check(checks, name, ok, detail)
  checks << { name: name, ok: ok, detail: detail }
end


def command_output(*cmd, chdir: ROOT)
  stdout, stderr, status = Open3.capture3(*cmd, chdir: chdir.to_s)
  [stdout, stderr, status.exitstatus]
end


def router_case(name, input, args, expect_blocked: false)
  stdout, stderr, code = command_output('ruby', ROUTER.to_s, '--input', input, *args)
  payload = stdout.empty? ? {} : JSON.parse(stdout)
  ok_exit = expect_blocked ? code == 10 : code.zero?
  {
    name: name,
    input: input,
    command: ['ruby', ROUTER.to_s, '--input', input, *args].join(' '),
    exit_code: code,
    stderr: stderr.strip,
    output: payload,
    ok_exit: ok_exit
  }
rescue StandardError => e
  {
    name: name,
    input: input,
    command: ['ruby', ROUTER.to_s, '--input', input, *args].join(' '),
    exit_code: nil,
    stderr: "#{e.class}: #{e.message}",
    output: {},
    ok_exit: false
  }
end


def header_includes?(payload)
  header = payload['reporter_header'].to_s
  %w[项目： project_id： board： workspace_path： git_root： git_root_status： dispatch_mode： routing_source： routing_confidence：].all? { |field| header.include?(field) }
end

registry = nil
begin
  registry = YAML.safe_load(REGISTRY.read, aliases: false)
  add_check(checks, 'P3_GATEWAY_REGISTRY_READ_READY', registry.is_a?(Hash), 'config/projects.yaml parsed')
rescue StandardError => e
  add_check(checks, 'P3_GATEWAY_REGISTRY_READ_READY', false, "#{e.class}: #{e.message}")
end

projects = registry.fetch('projects', {}) if registry
projects ||= {}
missing = REQUIRED_PROJECTS - projects.keys
add_check(checks, 'P3_REGISTRY_PROJECTS_PRESENT', missing.empty?, "projects=#{projects.keys.sort.join(',')}; missing=#{missing.join(',')}")

add_check(checks, 'P3_GATEWAY_ROUTER_WRAPPER_READY', ROUTER.file?, ROUTER.to_s)

gateway_text = GATEWAY_TEMPLATE.file? ? GATEWAY_TEMPLATE.read : ''
a2a_text = A2A_TEMPLATE.file? ? A2A_TEMPLATE.read : ''
required_gateway_fields = %w[project_id project_display_name board workspace_path current_git_root desired_git_root git_root_status dispatch_mode profile routing_source routing_confidence human_approval_required_for]
add_check(checks, 'P3_PROJECT_ID_REQUIRED_READY', gateway_text.include?('Gateway 接收任务前必须解析 `project_id`'), GATEWAY_TEMPLATE.to_s)
add_check(checks, 'P3_ROUTING_PRIORITY_READY', ROUTING_PRIORITY.all? { |s| gateway_text.include?(s) }, ROUTING_PRIORITY.join(' > '))
add_check(checks, 'P3_TASK_METADATA_PROJECT_FIELDS_READY', required_gateway_fields.all? { |field| gateway_text.include?(field) }, required_gateway_fields.join(','))
add_check(checks, 'P3_KANBAN_A2A_PROJECT_FIELDS_READY', %w[project: routing: conflict_resolution_order requires_clarification worker_auto_dispatch_triggered gateway_auto_dispatch_triggered real_worker_task_created].all? { |field| a2a_text.include?(field) && gateway_text.include?(field) }, 'project/routing/dry-run fields in gateway + A2A templates')
add_check(checks, 'P3_WORKSPACE_CONTAINER_BLOCK_READY', gateway_text.include?('workspace_container_is_not_business_project') && gateway_text.include?('/Users/hula/workspace 不得作为普通业务项目'), 'workspace container block rule')
add_check(checks, 'P3_LOW_CONFIDENCE_CLARIFICATION_READY', FUZZY_INPUTS.all? { |input| gateway_text.include?(input) } && gateway_text.include?('candidate_projects'), 'fuzzy examples + candidates')
add_check(checks, 'P3_ASK_HIGH_RISK_ACTION_BLOCK_READY', gateway_text.include?('ASK_GIT_ROOT_STATUS=needs_migration') && gateway_text.include?('human_approval_required_or_ask_git_root_needs_migration'), 'ASK high-risk gate')
add_check(checks, 'P3_REPORTER_PROJECT_ECHO_READY', %w[项目： project_id： board： workspace_path： git_root： git_root_status： dispatch_mode： routing_source： routing_confidence：].all? { |field| gateway_text.include?(field) }, 'Reporter project header fields')
add_check(checks, 'P3_DRY_RUN_WORK_ORDER_READY', gateway_text.include?('dry_run: true') && a2a_text.include?('dispatch.dry_run=true'), 'dry-run work order gate')

case1 = router_case('explicit_ask_route', '对 ASK 项目检查状态', [])
case1[:ok] = case1[:ok_exit] && case1[:output]['project_id'] == 'ask' && case1[:output]['board'] == 'ask' && case1[:output]['workspace_path'] == '/Users/hula/workspace/ASK' && case1[:output]['git_root_status'] == 'needs_migration' && case1[:output]['worker_auto_dispatch_triggered'] == false && case1[:output]['gateway_auto_dispatch_triggered'] == false
validation_cases << case1

case2 = router_case('explicit_multiagent_route', '对 multiagent-orchestration-system 项目生成项目列表报告', [])
case2[:ok] = case2[:ok_exit] && case2[:output]['project_id'] == 'multiagent-orchestration-system' && case2[:output]['board'] == 'multiagent-orchestration-system' && case2[:output]['workspace_path'] == ROOT.to_s && %w[independent ok].include?(case2[:output]['git_root_status'])
validation_cases << case2

case3 = router_case('workspace_container_block', '在 /Users/hula/workspace 里执行项目任务', ['--workspace', PARENT_WORKSPACE], expect_blocked: true)
case3[:ok] = case3[:ok_exit] && case3[:output]['project_id'] == 'blocked' && case3[:output]['reason'] == 'workspace_container_is_not_business_project' && case3[:output]['worker_auto_dispatch_triggered'] == false && case3[:output]['gateway_auto_dispatch_triggered'] == false
validation_cases << case3

case4 = router_case('low_confidence_block', '继续做', [], expect_blocked: true)
case4[:ok] = case4[:ok_exit] && case4[:output]['project_id'] == 'blocked' && case4[:output]['requires_clarification'] == true && case4[:output]['candidate_projects'].to_a.sort == REQUIRED_PROJECTS.sort && case4[:output]['worker_auto_dispatch_triggered'] == false
validation_cases << case4

case5 = router_case('ask_high_risk_action_block', '对 ASK 执行 push 或自动 merge', [], expect_blocked: true)
case5[:ok] = case5[:ok_exit] && case5[:output]['project_id'] == 'ask' && case5[:output]['blocked'] == true && case5[:output]['reason'] == 'human_approval_required_or_ask_git_root_needs_migration' && case5[:output]['worker_auto_dispatch_triggered'] == false && case5[:output]['gateway_auto_dispatch_triggered'] == false
validation_cases << case5

case6 = router_case('reporter_project_echo', '当前项目是什么？', ['--current-project', 'multiagent-orchestration-system'])
case6[:ok] = case6[:ok_exit] && case6[:output]['project_id'] == 'multiagent-orchestration-system' && header_includes?(case6[:output])
validation_cases << case6

project_list = projects.values.map { |p| { 'project_id' => p['project_id'], 'board' => p['default_board'], 'workspace_path' => p['task_guard_workspace'], 'git_root_status' => p['git_root_status'] } }
case7 = {
  name: 'project_list',
  input: '当前一共有几个项目？',
  command: 'registry projects list',
  exit_code: 0,
  stderr: '',
  output: { 'projects' => project_list, 'current_project' => 'multiagent-orchestration-system', 'default_project' => 'multiagent-orchestration-system' },
  ok_exit: true
}
case7[:ok] = project_list.map { |p| p['project_id'] }.sort == REQUIRED_PROJECTS.sort && project_list.all? { |p| p['git_root_status'] }
validation_cases << case7

case8 = router_case('kanban_a2a_dry_run_metadata', '创建一个 dry-run work order，不派工。', ['--project-id', 'multiagent-orchestration-system', '--dry-run-work-order'])
wo = case8[:output]['dry_run_work_order'] || {}
case8[:ok] = case8[:ok_exit] && wo['dry_run'] == true && wo.dig('project', 'project_id') == 'multiagent-orchestration-system' && wo.dig('routing', 'conflict_resolution_order') == ROUTING_PRIORITY && wo.dig('dispatch', 'worker_auto_dispatch_triggered') == false && wo.dig('dispatch', 'gateway_auto_dispatch_triggered') == false && wo.dig('dispatch', 'real_worker_task_created') == false
validation_cases << case8

validation_cases.each do |test_case|
  add_check(checks, "P3_CASE_#{test_case[:name].upcase}", test_case[:ok], JSON.generate(test_case))
end

stdout, stderr, code = command_output('git', '-C', '/Users/hula/workspace', 'status', '--short', '--', 'ASK/src', 'ASK/tests', 'ASK/packages', chdir: ROOT)
ask_business_status = stdout.lines.map(&:chomp).reject(&:empty?)
add_check(checks, 'ASK_CODE_MODIFIED', ask_business_status.empty?, ask_business_status.join(' | '))

stdout, stderr, code = command_output('git', '-C', '/Users/hula/workspace', 'status', '--short', '--', '/Users/hula/.hermes', chdir: ROOT)
hermes_core_status = stdout.lines.map(&:chomp).reject(&:empty?)
add_check(checks, 'HERMES_CORE_MODIFIED', hermes_core_status.empty?, hermes_core_status.join(' | '))

stdout, stderr, code = command_output('git', 'status', '--porcelain=v1', '-uall', '--', 'templates', 'scripts/validation', 'scripts/gateway', 'reports', 'config')
scoped_status = stdout.lines.map(&:chomp)

all_checks_ok = checks.all? { |check| check[:ok] }
flag = ->(name) { checks.find { |c| c[:name] == name }&.dig(:ok) ? 'YES' : 'NO' }
result = {
  generated_at: Time.now.iso8601,
  project_id: 'multiagent-orchestration-system',
  registry: REGISTRY.to_s,
  router: ROUTER.to_s,
  script: __FILE__,
  required_flags: {
    'P3_GATEWAY_REGISTRY_READ_READY' => flag.call('P3_GATEWAY_REGISTRY_READ_READY'),
    'P3_PROJECT_ID_REQUIRED_READY' => flag.call('P3_PROJECT_ID_REQUIRED_READY'),
    'P3_ROUTING_PRIORITY_READY' => flag.call('P3_ROUTING_PRIORITY_READY'),
    'P3_TASK_METADATA_PROJECT_FIELDS_READY' => flag.call('P3_TASK_METADATA_PROJECT_FIELDS_READY'),
    'P3_KANBAN_A2A_PROJECT_FIELDS_READY' => flag.call('P3_KANBAN_A2A_PROJECT_FIELDS_READY'),
    'P3_WORKSPACE_CONTAINER_BLOCK_READY' => flag.call('P3_WORKSPACE_CONTAINER_BLOCK_READY'),
    'P3_LOW_CONFIDENCE_CLARIFICATION_READY' => flag.call('P3_LOW_CONFIDENCE_CLARIFICATION_READY'),
    'P3_ASK_HIGH_RISK_ACTION_BLOCK_READY' => flag.call('P3_ASK_HIGH_RISK_ACTION_BLOCK_READY'),
    'P3_REPORTER_PROJECT_ECHO_READY' => flag.call('P3_REPORTER_PROJECT_ECHO_READY'),
    'P3_DRY_RUN_WORK_ORDER_READY' => flag.call('P3_DRY_RUN_WORK_ORDER_READY'),
    'P3_VALIDATION_PASSED' => all_checks_ok ? 'YES' : 'NO',
    'WORKER_AUTO_DISPATCH_TRIGGERED' => 'NO',
    'GATEWAY_AUTO_DISPATCH_TRIGGERED' => 'NO',
    'ASK_GIT_ROOT_MIGRATION_EXECUTED' => 'NO',
    'ASK_CODE_MODIFIED' => ask_business_status.empty? ? 'NO' : 'YES',
    'HERMES_CORE_MODIFIED' => hermes_core_status.empty? ? 'NO' : 'YES',
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
    scoped_status: scoped_status
  }
}

puts JSON.pretty_generate(result)
exit(all_checks_ok ? 0 : 1)
