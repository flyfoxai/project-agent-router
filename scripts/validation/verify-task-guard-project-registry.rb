#!/usr/bin/env ruby
# frozen_string_literal: true

require 'yaml'
require 'json'
require 'open3'
require 'pathname'
require 'time'

ROOT = Pathname.new(__dir__).join('..', '..').expand_path
REGISTRY = ROOT.join('config', 'projects.yaml')
TASK_GUARD_TEMPLATE = ROOT.join('templates', 'task-guard-project-registry-gate.md')
A2A_TEMPLATE = ROOT.join('templates', 'a2a-work-order-protocol.md')
P0_REPORT = ROOT.join('reports', 'project-overlay-registry-implementation-report.md')
P1_REPORT = ROOT.join('reports', 'p1-reporter-project-routing-report.md')
P2_REPORT = ROOT.join('reports', 'p2-task-guard-project-registry-report.md')

FORBIDDEN_MULTIAGENT_PATHS = [
  '.gitignore',
  'package.json',
  'pnpm-lock.yaml',
  'src',
  'packages',
  'ASK'
].freeze
FORBIDDEN_ASK_PARENT_REPO_PATHS = [
  'ASK/.gitignore',
  'ASK/package.json',
  'ASK/pnpm-lock.yaml',
  'ASK/src',
  'ASK/tests'
].freeze

REQUIRED_REGISTRY_PROJECTS = %w[ask project-agent-router].freeze
REQUIRED_TASK_GUARD_STRINGS = [
  'Task Guard Project Overlay Registry Gate',
  'config/projects.yaml',
  'project_id: "ask | project-agent-router | blocked"',
  '/Users/hula/workspace 是父级容器，不应作为普通业务项目执行。',
  'ASK_GIT_ROOT_STATUS=needs_migration',
  'project_id=blocked',
  '完成前检查清单'
].freeze
REQUIRED_A2A_STRINGS = [
  'Reporter 必须先读取 `config/projects.yaml`',
  'routing_policy.conflict_resolution_order',
  'project.project_id=blocked',
  '项目切换必须由新的 `WORK_ORDER`',
  'summary.conclusion_first'
].freeze
REQUIRED_REPORT_STRINGS = {
  P0_REPORT => ['Project Overlay Registry 实施报告', 'project_id=project-agent-router', 'task_guard 接入规划'],
  P1_REPORT => ['P1 Reporter 项目路由模板接入报告', 'REPORT_HEADER_REQUIRED=TRUE', 'FORBIDDEN_STATUS_START']
}.freeze

checks = []

def add_check(checks, name, ok, detail)
  checks << { name: name, ok: ok, detail: detail }
end

def command_output(*cmd, chdir: ROOT)
  stdout, stderr, status = Open3.capture3(*cmd, chdir: chdir.to_s)
  [stdout, stderr, status.exitstatus]
end

add_check(checks, 'ROOT_EXISTS', ROOT.directory?, ROOT.to_s)
add_check(checks, 'REGISTRY_EXISTS', REGISTRY.file?, REGISTRY.to_s)

registry = nil
begin
  registry = YAML.safe_load(REGISTRY.read, aliases: false)
  add_check(checks, 'REGISTRY_YAML_OK', registry.is_a?(Hash), 'YAML.safe_load succeeded')
rescue StandardError => e
  add_check(checks, 'REGISTRY_YAML_OK', false, "#{e.class}: #{e.message}")
end

if registry
  projects = registry.fetch('projects', {})
  missing_projects = REQUIRED_REGISTRY_PROJECTS - projects.keys
  add_check(checks, 'REGISTRY_PROJECTS_OK', missing_projects.empty?, "projects=#{projects.keys.sort.join(',')}; missing=#{missing_projects.join(',')}")

  policy = registry.fetch('routing_policy', {})
  add_check(checks, 'REGISTRY_MANUAL_DISPATCH_OK', policy['default_dispatch_mode'] == 'manual' && policy['gateway_auto_dispatch_allowed'] == false && policy['coder_concurrency_expansion_allowed'] == false, policy.inspect)
  add_check(checks, 'TASK_GUARD_POLICY_KEYS_OK', registry.dig('task_guard_policy', 'short_term_evidence_must_include').to_a.include?('project_id') && registry.dig('task_guard_policy', 'completion_requires').to_a.include?('forbidden_scope_checked'), registry.fetch('task_guard_policy', {}).inspect)

  ask = projects['ask'] || {}
  multiagent = projects['project-agent-router'] || {}
  add_check(checks, 'ASK_BOUNDARY_OK', ask['business_root'] == '/Users/hula/workspace/ASK' && ask['current_git_root'] == '/Users/hula/workspace' && ask['git_root_status'] == 'needs_migration', ask.inspect)
  add_check(checks, 'MULTIAGENT_BOUNDARY_OK', multiagent['business_root'] == ROOT.to_s && multiagent['current_git_root'] == ROOT.to_s && multiagent['git_root_status'] == 'independent', multiagent.inspect)
end

stdout, stderr, code = command_output('git', 'rev-parse', '--show-toplevel')
git_root = stdout.strip
add_check(checks, 'LIVE_MULTIAGENT_GIT_ROOT_OK', code.zero? && git_root == ROOT.to_s, "stdout=#{git_root.inspect}; stderr=#{stderr.strip.inspect}; exit=#{code}")

stdout, stderr, code = command_output('git', '-C', '/Users/hula/workspace/ASK', 'rev-parse', '--show-toplevel', chdir: ROOT)
ask_git_root = stdout.strip
add_check(checks, 'LIVE_ASK_GIT_ROOT_STATUS_OK', code.zero? && ask_git_root == '/Users/hula/workspace', "stdout=#{ask_git_root.inspect}; stderr=#{stderr.strip.inspect}; exit=#{code}")

[TASK_GUARD_TEMPLATE, A2A_TEMPLATE].each do |path|
  add_check(checks, "#{path.basename.to_s.upcase}_EXISTS", path.file?, path.to_s)
end

if TASK_GUARD_TEMPLATE.file?
  text = TASK_GUARD_TEMPLATE.read
  missing = REQUIRED_TASK_GUARD_STRINGS.reject { |needle| text.include?(needle) }
  add_check(checks, 'TASK_GUARD_TEMPLATE_STRINGS_OK', missing.empty?, "missing=#{missing.join(' | ')}")
end

if A2A_TEMPLATE.file?
  text = A2A_TEMPLATE.read
  missing = REQUIRED_A2A_STRINGS.reject { |needle| text.include?(needle) }
  add_check(checks, 'A2A_TEMPLATE_STRINGS_OK', missing.empty?, "missing=#{missing.join(' | ')}")
end

REQUIRED_REPORT_STRINGS.each do |path, needles|
  add_check(checks, "#{path.basename.to_s.upcase}_EXISTS", path.file?, path.to_s)
  next unless path.file?

  text = path.read
  missing = needles.reject { |needle| text.include?(needle) }
  add_check(checks, "#{path.basename.to_s.upcase}_STRINGS_OK", missing.empty?, "missing=#{missing.join(' | ')}")
end

stdout, stderr, code = command_output('git', 'status', '--porcelain=v1', '-uall', '--', *FORBIDDEN_MULTIAGENT_PATHS)
forbidden_multiagent_status = stdout.lines.map(&:chomp).reject(&:empty?)
add_check(checks, 'FORBIDDEN_MULTIAGENT_PATHS_CLEAN', code.zero? && forbidden_multiagent_status.empty?, forbidden_multiagent_status.empty? ? 'no forbidden multiagent path status' : forbidden_multiagent_status.join(' | '))

stdout, stderr, code = command_output('git', '-C', '/Users/hula/workspace', 'status', '--porcelain=v1', '-uall', '--', *FORBIDDEN_ASK_PARENT_REPO_PATHS, chdir: ROOT)
forbidden_ask_status = stdout.lines.map(&:chomp).reject(&:empty?)
add_check(checks, 'FORBIDDEN_ASK_PARENT_REPO_PATHS_CLEAN', code.zero? && forbidden_ask_status.empty?, forbidden_ask_status.empty? ? 'no forbidden ASK path status' : forbidden_ask_status.join(' | '))

stdout, stderr, code = command_output('git', 'status', '--porcelain=v1', '-uall', '--', 'config', 'templates', 'reports', 'scripts/validation')
scoped_status = stdout.lines.map(&:chomp)
add_check(checks, 'SCOPED_STATUS_READABLE', code.zero?, scoped_status.join(' | '))

result = {
  generated_at: Time.now.iso8601,
  project_id: 'project-agent-router',
  workspace_path: ROOT.to_s,
  git_root: git_root,
  script: __FILE__,
  checks: checks,
  summary: {
    total: checks.length,
    passed: checks.count { |check| check[:ok] },
    failed: checks.count { |check| !check[:ok] },
    forbidden_multiagent_status: forbidden_multiagent_status,
    forbidden_ask_status: forbidden_ask_status,
    scoped_status: scoped_status
  }
}

puts JSON.pretty_generate(result)
exit(result[:summary][:failed].zero? ? 0 : 1)
