#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'yaml'
require 'optparse'
require 'open3'
require 'pathname'
require 'time'
require 'fileutils'

ROOT = Pathname.new(__dir__).join('..', '..').expand_path
REGISTRY = ROOT.join('config', 'projects.yaml')
GATEWAY_ROUTER = ROOT.join('scripts', 'gateway', 'project-router.rb')
STATE_ROOT = ROOT.join('state', 'conversations').expand_path
ROUTING_PRIORITY_TEXT = '显式项目 > 当前项目 > 默认项目 > 通用 ASK/分析问题 > system/meta > 澄清'
LOW_CONFIDENCE_TEXTS = ['继续做', '处理这个项目', '派给 worker', '让 agents 开始', '把它改了'].freeze

options = {
  message_json: nil,
  state_file: ROOT.join('state', 'conversations', 'dry-run-state.json').to_s
}

OptionParser.new do |opts|
  opts.banner = 'Usage: project-conversation-router.rb --message-json JSON [--state-file PATH]'
  opts.on('--message-json JSON', 'ConversationMessage JSON') { |v| options[:message_json] = v }
  opts.on('--state-file PATH', 'Dry-run state file under state/conversations/') { |v| options[:state_file] = v }
end.parse!


def load_registry
  YAML.safe_load(REGISTRY.read, aliases: false)
rescue StandardError => e
  warn "registry_error=#{e.class}: #{e.message}"
  nil
end


def project_lookup(projects, raw)
  return nil if raw.nil? || raw.to_s.strip.empty?

  needle = raw.to_s.strip.downcase
  projects.values.find do |project|
    ([project['project_id'], project['display_name']] + project.fetch('aliases', [])).compact.any? do |value|
      value.to_s.downcase == needle
    end
  end
end


def detect_project_in_text(projects, text)
  down = text.to_s.downcase
  projects.values.find do |project|
    ([project['project_id'], project['display_name']] + project.fetch('aliases', [])).compact.any? do |value|
      token = value.to_s.downcase
      !token.empty? && down.include?(token)
    end
  end
end


def safe_state_file(path)
  candidate = Pathname.new(path).expand_path
  unless candidate.to_s.start_with?(STATE_ROOT.to_s + '/') || candidate == STATE_ROOT.join('dry-run-state.json')
    raise ArgumentError, "state_file_must_be_under=#{STATE_ROOT}"
  end
  candidate
end


def load_state(path)
  if path.file?
    payload = JSON.parse(path.read)
    payload.is_a?(Hash) ? payload : { 'version' => 1, 'conversations' => {} }
  else
    { 'version' => 1, 'conversations' => {} }
  end
rescue JSON::ParserError
  { 'version' => 1, 'conversations' => {} }
end


def save_state(path, state)
  FileUtils.mkdir_p(path.dirname)
  path.write(JSON.pretty_generate(state) + "\n")
end


def conversation_key(message)
  channel = message.fetch('channel')
  conversation_id = message.fetch('conversation_id')
  user_id = message.fetch('user_id')
  [channel, conversation_id, user_id].join(':')
end


def gateway_route(args)
  stdout, stderr, status = Open3.capture3('ruby', GATEWAY_ROUTER.to_s, *args, chdir: ROOT.to_s)
  [stdout.empty? ? {} : JSON.parse(stdout), stderr, status.exitstatus]
rescue StandardError => e
  [{ 'project_id' => 'blocked', 'reason' => "gateway_route_error: #{e.class}: #{e.message}" }, '', 10]
end


def neutral_project_fields(route)
  {
    'project_id' => route['project_id'] == 'blocked' ? 'blocked' : route['project_id'],
    'project_display_name' => route['project_display_name'],
    'project_label' => route['project_display_name'],
    'board' => route['board'],
    'workspace_path' => route['workspace_path'],
    'git_root' => route['current_git_root'],
    'git_root_status' => route['git_root_status'],
    'dispatch_mode' => route['dispatch_mode'] || 'manual',
    'reporter_header' => route['reporter_header'],
    'dry_run_work_order' => route['dry_run_work_order']
  }
end


def project_response_kwargs(fields)
  {
    project_id: fields['project_id'],
    project_display_name: fields['project_display_name'],
    project_label: fields['project_label'],
    board: fields['board'],
    workspace_path: fields['workspace_path'],
    git_root: fields['git_root'],
    git_root_status: fields['git_root_status'],
    dispatch_mode: fields['dispatch_mode'],
    reporter_header: fields['reporter_header'],
    dry_run_work_order: fields['dry_run_work_order']
  }
end


def base_response(mode:, project_id:, project_display_name:, routing_source:, routing_confidence:, requires_clarification:, response_text:, reporter_header: nil, project_label: nil, board: nil, workspace_path: nil, git_root: nil, git_root_status: nil, dispatch_mode: 'manual', dry_run_work_order: nil, current_project: nil, default_project: nil, actions: {})
  {
    'mode' => mode,
    'project_id' => project_id,
    'project_display_name' => project_display_name,
    'routing_source' => routing_source,
    'routing_confidence' => routing_confidence,
    'requires_clarification' => requires_clarification,
    'response_text' => response_text,
    'reporter_header' => reporter_header,
    'project_label' => project_label,
    'board' => board,
    'workspace_path' => workspace_path,
    'git_root' => git_root,
    'git_root_status' => git_root_status,
    'dispatch_mode' => dispatch_mode,
    'actions' => {
      'update_current_project' => actions.fetch('update_current_project', 'unchanged'),
      'update_default_project' => actions.fetch('update_default_project', 'unchanged')
    },
    'current_project' => current_project,
    'default_project' => default_project,
    'dry_run_work_order' => dry_run_work_order,
    'worker_auto_dispatch_triggered' => false,
    'gateway_auto_dispatch_triggered' => false
  }
end


def list_projects_response(projects, entry)
  list = projects.values.sort_by { |p| p['project_id'] }.map do |project|
    {
      'project_id' => project['project_id'],
      'display_name' => project['display_name'],
      'board' => project['default_board'],
      'workspace_path' => project.fetch('task_guard_workspace', project['project_root']),
      'git_root' => project['current_git_root'],
      'git_root_status' => project['git_root_status'],
      'is_current' => entry['current_project'] == project['project_id'],
      'is_default' => entry['default_project'] == project['project_id']
    }
  end
  text = "当前一共有 #{list.length} 个项目：" + list.map { |p| "#{p['project_id']}(#{p['display_name']})" }.join('、')
  resp = base_response(
    mode: 'project_command',
    project_id: nil,
    project_display_name: nil,
    routing_source: 'project_list',
    routing_confidence: 'high',
    requires_clarification: false,
    response_text: text,
    current_project: entry['current_project'],
    default_project: entry['default_project']
  )
  resp['projects'] = list
  resp
end


def current_project_response(projects, entry)
  current = entry['current_project']
  default = entry['default_project']
  effective = current || default
  text = if effective
           "当前项目=#{current || '未设置'}；默认项目=#{default || '未设置'}；后续未显式指定项目时按 #{effective} 处理。路由优先级：#{ROUTING_PRIORITY_TEXT}。"
         else
           "当前项目未设置；默认项目未设置。后续未指定项目时不会进入普通业务项目，需要显式选择项目。路由优先级：#{ROUTING_PRIORITY_TEXT}。"
         end
  base_response(
    mode: 'project_command',
    project_id: effective,
    project_display_name: effective && projects[effective]&.fetch('display_name'),
    routing_source: effective ? (current ? 'current_project' : 'default_project') : 'project_current_empty',
    routing_confidence: effective ? 'high' : 'medium',
    requires_clarification: false,
    response_text: text,
    current_project: current,
    default_project: default
  )
end


def use_project_response(project, entry, message, state, key, state_file)
  route, = gateway_route(['--input', message['text'].to_s, '--project-id', project['project_id'], '--dry-run-work-order'])
  entry['current_project'] = project['project_id']
  entry['updated_at'] = Time.now.iso8601
  entry['last_routing_source'] = 'project_use'
  entry['last_message_id'] = message['message_id']
  state['conversations'][key] = entry
  save_state(state_file, state)
  fields = neutral_project_fields(route)
  base_response(
    mode: 'project_command',
    routing_source: 'explicit_project',
    routing_confidence: 'high',
    requires_clarification: false,
    response_text: "已切换当前项目为 #{project['project_id']}（#{project['display_name']}）。不会创建 worker，不写 Kanban，dispatch_mode=manual。",
    current_project: entry['current_project'],
    default_project: entry['default_project'],
    actions: { 'update_current_project' => project['project_id'] },
    **project_response_kwargs(fields)
  )
end


def default_project_response(project, entry, message, state, key, state_file)
  route, = gateway_route(['--input', message['text'].to_s, '--project-id', project['project_id'], '--dry-run-work-order'])
  entry['default_project'] = project['project_id']
  entry['updated_at'] = Time.now.iso8601
  entry['last_routing_source'] = 'project_default'
  entry['last_message_id'] = message['message_id']
  state['conversations'][key] = entry
  save_state(state_file, state)
  fields = neutral_project_fields(route)
  base_response(
    mode: 'project_command',
    routing_source: 'explicit_project',
    routing_confidence: 'high',
    requires_clarification: false,
    response_text: "已设置默认项目为 #{project['project_id']}（#{project['display_name']}）。不覆盖当前项目。不会创建 worker，不写 Kanban。",
    current_project: entry['current_project'],
    default_project: entry['default_project'],
    actions: { 'update_default_project' => project['project_id'] },
    **project_response_kwargs(fields)
  )
end


def clear_project_response(entry, message, state, key, state_file)
  entry['current_project'] = nil
  entry['updated_at'] = Time.now.iso8601
  entry['last_routing_source'] = 'project_clear'
  entry['last_message_id'] = message['message_id']
  state['conversations'][key] = entry
  save_state(state_file, state)
  base_response(
    mode: 'project_command',
    project_id: nil,
    project_display_name: nil,
    routing_source: 'project_clear',
    routing_confidence: 'high',
    requires_clarification: false,
    response_text: "已清空当前项目；默认项目保留为 #{entry['default_project'] || '未设置'}。",
    current_project: nil,
    default_project: entry['default_project'],
    actions: { 'update_current_project' => nil }
  )
end

begin
  raise ArgumentError, 'missing --message-json' if options[:message_json].nil?

  message = JSON.parse(options[:message_json])
  %w[channel conversation_id user_id message_id text timestamp metadata].each { |field| message.fetch(field) }
  state_file = safe_state_file(options[:state_file])
  registry = load_registry
  raise 'registry_missing_or_invalid' unless registry.is_a?(Hash) && registry['projects'].is_a?(Hash)

  projects = registry.fetch('projects')
  state = load_state(state_file)
  state['version'] ||= 1
  state['conversations'] ||= {}
  key = conversation_key(message)
  entry = state['conversations'][key] || {
    'current_project' => nil,
    'default_project' => nil,
    'updated_at' => nil,
    'last_routing_source' => nil,
    'last_message_id' => nil
  }

  text = message['text'].to_s.strip
  lower = text.downcase

  response = if text == '/project list' || ['当前一共有几个项目？', '现在有哪些项目？'].include?(text)
               list_projects_response(projects, entry)
             elsif text == '/project current' || ['当前项目是什么？', '我下面说的话对哪个项目有效？'].include?(text)
               current_project_response(projects, entry)
             elsif text == '/project clear' || text == '取消当前项目'
               clear_project_response(entry, message, state, key, state_file)
             elsif (m = text.match(%r{\A/project\s+use\s+(.+)\z}i))
               project = project_lookup(projects, m[1])
               project ? use_project_response(project, entry, message, state, key, state_file) : nil
             elsif (m = text.match(%r{\A/project\s+default\s+(.+)\z}i))
               project = project_lookup(projects, m[1])
               project ? default_project_response(project, entry, message, state, key, state_file) : nil
             elsif lower.start_with?('/ask') || text.include?('只做通用分析')
               base_response(
                 mode: 'ask',
                 project_id: nil,
                 project_display_name: nil,
                 routing_source: 'ask_mode',
                 routing_confidence: 'high',
                 requires_clarification: false,
                 response_text: '已进入通用分析模式，不进入普通业务项目，不创建 worker。',
                 current_project: entry['current_project'],
                 default_project: entry['default_project']
               )
             elsif text == '/system status' || text == '/orchestration status'
               base_response(
                 mode: 'system_meta',
                 project_id: nil,
                 project_display_name: nil,
                 routing_source: 'system_meta',
                 routing_confidence: 'high',
                 requires_clarification: false,
                 response_text: '这是系统/编排状态查询，不进入普通业务项目；P4 dry-run 不接生产 webhook，不派发 worker。',
                 current_project: entry['current_project'],
                 default_project: entry['default_project']
               )
             elsif (text.start_with?('切到 ') || text.start_with?('接下来都按 ')) && (project = detect_project_in_text(projects, text))
               use_project_response(project, entry, message, state, key, state_file)
             elsif LOW_CONFIDENCE_TEXTS.include?(text) && entry['current_project'].nil? && entry['default_project'].nil?
               route, = gateway_route(['--input', text])
               fields = neutral_project_fields(route)
               base_response(
                 mode: 'blocked',
                 routing_source: 'blocked_clarification',
                 routing_confidence: 'blocked',
                 requires_clarification: true,
                 response_text: "无法判断要作用于哪个项目，请先使用 /project use <project> 或明确项目名。可选项目：#{projects.keys.sort.join(', ')}。",
                 current_project: entry['current_project'],
                 default_project: entry['default_project'],
                 **project_response_kwargs(fields)
               )
             else
               explicit = detect_project_in_text(projects, text)
               target_id = explicit&.fetch('project_id') || entry['current_project'] || entry['default_project']
               if target_id && projects[target_id]
                 source = explicit ? 'explicit_project' : (entry['current_project'] ? 'current_project' : 'default_project')
                 route_args = ['--input', text, '--project-id', target_id, '--dry-run-work-order']
                 route, = gateway_route(route_args)
                 fields = neutral_project_fields(route)
                 base_response(
                   mode: 'project_task',
                   routing_source: source,
                   routing_confidence: 'high',
                   requires_clarification: false,
                   response_text: "已按 #{target_id} 生成 dry-run 项目路由；dispatch_mode=manual，不创建 worker。",
                   current_project: entry['current_project'],
                   default_project: entry['default_project'],
                   **project_response_kwargs(fields)
                 )
               else
                 route, = gateway_route(['--input', text])
                 fields = neutral_project_fields(route)
                 base_response(
                   mode: 'blocked',
                   routing_source: 'blocked_clarification',
                   routing_confidence: 'blocked',
                   requires_clarification: true,
                   response_text: "低置信度：未能确定项目。请明确项目，例如 /project use ask 或 /project use multiagent-orchestration-system。",
                   current_project: entry['current_project'],
                   default_project: entry['default_project'],
                   **project_response_kwargs(fields)
                 )
               end
             end

  if response.nil?
    response = base_response(
      mode: 'blocked',
      project_id: 'blocked',
      project_display_name: 'blocked',
      routing_source: 'blocked_clarification',
      routing_confidence: 'blocked',
      requires_clarification: true,
      response_text: '项目不存在或无法识别，请使用 /project list 查看可选项目。',
      project_label: 'blocked',
      dispatch_mode: 'blocked',
      current_project: entry['current_project'],
      default_project: entry['default_project']
    )
  end

  # Read-only commands still update only last observed metadata in the project-local dry-run state.
  unless %w[project_use project_default project_clear].include?(entry['last_routing_source']) && entry['last_message_id'] == message['message_id']
    entry['updated_at'] = Time.now.iso8601
    entry['last_routing_source'] = response['routing_source']
    entry['last_message_id'] = message['message_id']
    state['conversations'][key] = entry
    save_state(state_file, state)
  end

  puts JSON.pretty_generate(response)
  exit(response['mode'] == 'blocked' ? 10 : 0)
rescue StandardError => e
  warn "conversation_router_error=#{e.class}: #{e.message}"
  payload = base_response(
    mode: 'blocked',
    project_id: 'blocked',
    project_display_name: 'blocked',
    routing_source: 'blocked_clarification',
    routing_confidence: 'blocked',
    requires_clarification: true,
    response_text: "conversation router error: #{e.class}: #{e.message}",
    project_label: 'blocked',
    dispatch_mode: 'blocked',
    actions: {}
  )
  puts JSON.pretty_generate(payload)
  exit 10
end
