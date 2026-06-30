#!/usr/bin/env ruby
# frozen_string_literal: true

require 'yaml'
require 'json'
require 'optparse'
require 'pathname'

ROOT = Pathname.new(__dir__).join('..', '..').expand_path
REGISTRY = ROOT.join('config', 'projects.yaml')
PARENT_WORKSPACE = '/Users/hula/workspace'
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
HIGH_RISK_WORDS = %w[push merge publish commit].freeze
HIGH_RISK_REGEX = /(push|merge|publish|commit|自动\s*merge|自动\s*commit|迁移\s*\.git|Git root migration|扩大.*coder|并发)/i

options = {
  input: '',
  project_id: nil,
  alias_name: nil,
  board: nil,
  workspace_path: nil,
  current_project: nil,
  default_project: nil,
  action: nil,
  dry_run_work_order: false,
  system_meta: false
}

OptionParser.new do |opts|
  opts.banner = 'Usage: project-router.rb [options]'
  opts.on('--input TEXT', 'Natural language input') { |v| options[:input] = v }
  opts.on('--project-id ID', 'Explicit project_id') { |v| options[:project_id] = v }
  opts.on('--alias NAME', 'Explicit project alias') { |v| options[:alias_name] = v }
  opts.on('--board SLUG', 'Board slug') { |v| options[:board] = v }
  opts.on('--workspace PATH', 'Workspace path') { |v| options[:workspace_path] = v }
  opts.on('--current-project ID', 'Current project state') { |v| options[:current_project] = v }
  opts.on('--default-project ID', 'Default project state') { |v| options[:default_project] = v }
  opts.on('--action ACTION', 'Requested action') { |v| options[:action] = v }
  opts.on('--dry-run-work-order', 'Return dry-run work order metadata') { options[:dry_run_work_order] = true }
  opts.on('--system-meta', 'Treat as system/meta task') { options[:system_meta] = true }
end.parse!


def load_registry
  YAML.safe_load(REGISTRY.read, aliases: false)
rescue StandardError => e
  warn "registry_error=#{e.class}: #{e.message}"
  nil
end


def blocked_payload(reason, source:, workspace_path: 'unknown', candidates: [])
  {
    'project_id' => 'blocked',
    'project_display_name' => 'blocked',
    'board' => 'blocked',
    'workspace_path' => workspace_path || 'unknown',
    'current_git_root' => 'unknown',
    'desired_git_root' => 'unknown',
    'git_root_status' => 'blocked',
    'dispatch_mode' => 'blocked',
    'profile' => 'blocked',
    'routing_source' => source,
    'routing_confidence' => 'blocked',
    'requires_clarification' => true,
    'blocked' => true,
    'reason' => reason,
    'candidate_projects' => candidates,
    'human_approval_required_for' => %w[push merge publish git_root_migration coder_concurrency_expansion],
    'worker_auto_dispatch_triggered' => false,
    'gateway_auto_dispatch_triggered' => false,
    'real_worker_task_created' => false
  }
end


def project_payload(project, source:, confidence: 'high')
  {
    'project_id' => project.fetch('project_id'),
    'project_display_name' => project.fetch('display_name'),
    'board' => project.fetch('default_board'),
    'workspace_path' => project.fetch('task_guard_workspace', project.fetch('project_root')),
    'current_git_root' => project.fetch('current_git_root'),
    'desired_git_root' => project.fetch('desired_git_root'),
    'git_root_status' => project.fetch('git_root_status'),
    'dispatch_mode' => project.dig('dispatch', 'mode') || 'manual',
    'profile' => project.fetch('default_profile'),
    'routing_source' => source,
    'routing_confidence' => confidence,
    'requires_clarification' => false,
    'human_approval_required_for' => %w[push merge publish git_root_migration coder_concurrency_expansion],
    'worker_auto_dispatch_triggered' => false,
    'gateway_auto_dispatch_triggered' => false,
    'real_worker_task_created' => false
  }
end


def dry_run_work_order(payload)
  {
    'message_type' => 'WORK_ORDER',
    'protocol_version' => 'ask-a2a-v1',
    'dry_run' => true,
    'project' => {
      'project_id' => payload['project_id'],
      'display_name' => payload['project_display_name'],
      'board' => payload['board'],
      'workspace_path' => payload['workspace_path'],
      'current_git_root' => payload['current_git_root'],
      'desired_git_root' => payload['desired_git_root'],
      'git_root_status' => payload['git_root_status'],
      'dispatch_mode' => payload['dispatch_mode']
    },
    'routing' => {
      'source' => payload['routing_source'],
      'confidence' => payload['routing_confidence'],
      'conflict_resolution_order' => ROUTING_PRIORITY,
      'requires_clarification' => payload['requires_clarification']
    },
    'dispatch' => {
      'mode' => 'manual',
      'gateway_allowed' => false,
      'worker_auto_dispatch_triggered' => false,
      'gateway_auto_dispatch_triggered' => false,
      'real_worker_task_created' => false
    }
  }
end


def reporter_header(payload)
  <<~TEXT
    项目：#{payload['project_display_name']}
    project_id：#{payload['project_id']}
    board：#{payload['board']}
    workspace_path：#{payload['workspace_path']}
    git_root：#{payload['current_git_root']}
    git_root_status：#{payload['git_root_status']}
    dispatch_mode：#{payload['dispatch_mode']}
    routing_source：#{payload['routing_source']}
    routing_confidence：#{payload['routing_confidence']}
  TEXT
end

registry = load_registry
unless registry.is_a?(Hash) && registry.dig('projects', 'ask') && registry.dig('projects', 'multiagent-orchestration-system')
  puts JSON.pretty_generate(blocked_payload('registry_missing_or_invalid', source: 'blocked_clarification'))
  exit 2
end

projects = registry.fetch('projects')
candidates = projects.keys.sort
input = options[:input].to_s
workspace = options[:workspace_path]
action_text = [options[:action], input].compact.join(' ')

if workspace == PARENT_WORKSPACE && !options[:system_meta]
  payload = blocked_payload('workspace_container_is_not_business_project', source: 'workspace_path', workspace_path: workspace, candidates: candidates)
elsif FUZZY_INPUTS.include?(input.strip) && options.values_at(:project_id, :alias_name, :board, :workspace_path, :current_project, :default_project).compact.empty?
  payload = blocked_payload('low_confidence_requires_clarification', source: 'blocked_clarification', candidates: candidates)
else
  source = nil
  project = nil

  if options[:project_id] && projects[options[:project_id]]
    source = 'explicit_project_id'
    project = projects[options[:project_id]]
  end

  if project.nil? && options[:alias_name]
    source = 'explicit_project_alias'
    project = projects.values.find { |p| p.fetch('aliases', []).map(&:downcase).include?(options[:alias_name].downcase) || p['project_id'].downcase == options[:alias_name].downcase }
  end

  if project.nil?
    alias_match = projects.values.find { |p| ([p['project_id'], p['display_name']] + p.fetch('aliases', [])).compact.any? { |a| input.downcase.include?(a.downcase) } }
    if alias_match
      source = alias_match['project_id'] == input.strip ? 'explicit_project_id' : 'explicit_project_alias'
      project = alias_match
    end
  end

  if project.nil? && options[:board]
    source = 'board_slug'
    project = projects.values.find { |p| p['default_board'] == options[:board] }
  end

  if project.nil? && workspace
    source = 'workspace_path'
    matches = projects.values.select { |p| [p['business_root'], p['project_root'], p['task_guard_workspace']].include?(workspace) }
    project = matches.first if matches.length == 1
  end

  if project.nil? && options[:current_project] && projects[options[:current_project]]
    source = 'current_project'
    project = projects[options[:current_project]]
  end

  if project.nil? && options[:default_project] && projects[options[:default_project]]
    source = 'default_project'
    project = projects[options[:default_project]]
  end

  if project.nil? && options[:system_meta]
    payload = blocked_payload('system_meta_not_business_project', source: 'system_meta', workspace_path: workspace || 'unknown', candidates: candidates)
  elsif project.nil?
    payload = blocked_payload('low_confidence_requires_clarification', source: 'blocked_clarification', candidates: candidates)
  else
    payload = project_payload(project, source: source)
    if project['project_id'] == 'ask' && action_text.match?(HIGH_RISK_REGEX)
      payload['blocked'] = true
      payload['reason'] = 'human_approval_required_or_ask_git_root_needs_migration'
    end
  end
end

payload['reporter_header'] = reporter_header(payload)
payload['ASK_GIT_ROOT_STATUS'] = 'needs_migration' if payload['project_id'] == 'ask'
payload['dry_run_work_order'] = dry_run_work_order(payload) if options[:dry_run_work_order]

puts JSON.pretty_generate(payload)
exit(payload['blocked'] ? 10 : 0)
