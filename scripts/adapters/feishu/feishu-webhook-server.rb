#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'optparse'
require 'pathname'
require 'webrick'
require 'fileutils'
require 'open3'
require 'tempfile'
require 'yaml'

ROOT = Pathname.new(__dir__).join('..', '..', '..').expand_path
GATE = ROOT.join('scripts', 'adapters', 'feishu', 'feishu-webhook-security-gate.rb')
DEFAULT_CONFIG = ROOT.join('config', 'feishu-command-adapter.yaml').to_s
DEFAULT_STATE = ROOT.join('state', 'conversations', 'feishu-command-state.json').to_s
DEFAULT_AUDIT = ROOT.join('logs', 'feishu-adapter', 'feishu-command-audit.jsonl').to_s
DEFAULT_IDEMPOTENCY = ROOT.join('state', 'conversations', 'feishu-idempotency-state.json').to_s
DEFAULT_RATE_LIMIT = ROOT.join('state', 'conversations', 'feishu-rate-limit-state.json').to_s
DEFAULT_LOCK = ROOT.join('state', 'conversations', 'feishu-command-state.lock').to_s

options = {
  host: '127.0.0.1',
  port: 0,
  config: DEFAULT_CONFIG,
  state_file: DEFAULT_STATE,
  audit_log: DEFAULT_AUDIT,
  idempotency_state: DEFAULT_IDEMPOTENCY,
  rate_limit_state: DEFAULT_RATE_LIMIT,
  lock_file: DEFAULT_LOCK,
  ready_json: false,
  disabled: false
}

OptionParser.new do |opts|
  opts.banner = 'Usage: feishu-webhook-server.rb --host HOST --port PORT [options]'
  opts.on('--host HOST', 'Bind host') { |v| options[:host] = v }
  opts.on('--port PORT', Integer, 'Bind port, 0 means auto-select') { |v| options[:port] = v }
  opts.on('--config PATH', 'Adapter YAML config') { |v| options[:config] = v }
  opts.on('--state-file PATH', 'Conversation state file') { |v| options[:state_file] = v }
  opts.on('--audit-log PATH', 'Audit JSONL file') { |v| options[:audit_log] = v }
  opts.on('--idempotency-state PATH', 'Idempotency state file') { |v| options[:idempotency_state] = v }
  opts.on('--rate-limit-state PATH', 'Rate-limit state file') { |v| options[:rate_limit_state] = v }
  opts.on('--lock-file PATH', 'Lock file') { |v| options[:lock_file] = v }
  opts.on('--ready-json', 'Print a JSON readiness line to stdout') { options[:ready_json] = true }
  opts.on('--disabled', 'Disable ingress and return blocked responses') { options[:disabled] = true }
end.parse!

STDOUT.sync = true
Thread.abort_on_exception = true


def read_config(path)
  YAML.safe_load(Pathname.new(path).read, aliases: false) || {}
rescue StandardError
  {}
end


def disabled_by_env?
  ENV['FEISHU_WEBHOOK_DISABLED'].to_s == '1'
end


def normalize_path(path)
  value = path.to_s.strip
  return '/feishu/events' if value.empty?
  value.start_with?('/') ? value : "/#{value}"
end


def ready_payload(port:, webhook_path:, healthz_path:, readyz_path:, disabled:, config_path:)
  {
    'status' => 'ready',
    'host' => '127.0.0.1',
    'port' => port,
    'webhook_path' => webhook_path,
    'healthz_path' => healthz_path,
    'readyz_path' => readyz_path,
    'config' => config_path,
    'disabled' => disabled,
    'gate' => GATE.to_s
  }
end


def gate_command(body_json:, headers_json:, config:, state_file:, audit_log:, idempotency_state:, rate_limit_state:, lock_file:, disabled:)
  command = [
    'ruby', GATE.to_s,
    '--body-json', body_json,
    '--headers-json', headers_json,
    '--config', config,
    '--state-file', state_file,
    '--audit-log', audit_log,
    '--idempotency-state', idempotency_state,
    '--rate-limit-state', rate_limit_state,
    '--lock-file', lock_file
  ]
  command << '--disabled' if disabled
  command
end


def run_gate(payload, headers, options)
  FileUtils.mkdir_p(File.dirname(options[:state_file]))
  FileUtils.mkdir_p(File.dirname(options[:audit_log]))
  FileUtils.mkdir_p(File.dirname(options[:idempotency_state]))
  FileUtils.mkdir_p(File.dirname(options[:rate_limit_state]))
  FileUtils.mkdir_p(File.dirname(options[:lock_file]))

  body_file = Tempfile.new(['feishu-webhook-body', '.json'])
  headers_file = Tempfile.new(['feishu-webhook-headers', '.json'])
  body_file.write(JSON.generate(payload))
  body_file.close
  headers_file.write(JSON.generate(headers))
  headers_file.close

  stdout, stderr, status = Open3.capture3(
    *gate_command(
      body_json: body_file.path,
      headers_json: headers_file.path,
      config: options[:config],
      state_file: options[:state_file],
      audit_log: options[:audit_log],
      idempotency_state: options[:idempotency_state],
      rate_limit_state: options[:rate_limit_state],
      lock_file: options[:lock_file],
      disabled: options[:disabled]
    ),
    chdir: ROOT.to_s
  )
  [stdout, stderr, status]
ensure
  body_file&.unlink
  headers_file&.unlink
end


def read_json_request(req)
  body = req.body.to_s
  return {} if body.empty?

  JSON.parse(body)
rescue JSON::ParserError
  {}
end


def read_headers(req)
  headers = {}
  req.header.each do |key, values|
    headers[key] = Array(values).join(',')
  end
  headers
end


def json_response(status:, payload:)
  [status, { 'Content-Type' => 'application/json; charset=utf-8' }, JSON.pretty_generate(payload)]
end

config = read_config(options[:config])
webhook_path = normalize_path(config.dig('deployment', 'webhook') || '/feishu/events')
healthz_path = normalize_path(config.dig('deployment', 'healthz') || '/healthz')
readyz_path = normalize_path(config.dig('deployment', 'readyz') || '/readyz')

server = WEBrick::HTTPServer.new(
  BindAddress: options[:host],
  Port: options[:port],
  AccessLog: [],
  Logger: WEBrick::Log.new($stderr, WEBrick::Log::WARN)
)

server.mount_proc('/healthz') do |_req, res|
  res.status = 200
  res['Content-Type'] = 'application/json; charset=utf-8'
  res.body = JSON.generate({ 'status' => 'ok' })
end

server.mount_proc('/readyz') do |_req, res|
  res.status = 200
  res['Content-Type'] = 'application/json; charset=utf-8'
  res.body = JSON.generate(
    'status' => 'ok',
    'webhook_path' => webhook_path,
    'healthz_path' => healthz_path,
    'readyz_path' => readyz_path,
    'disabled' => options[:disabled] || disabled_by_env? || config['webhook_enabled'] == false
  )
end

server.mount_proc(webhook_path) do |req, res|
  if req.request_method != 'POST'
    res.status = 405
    res['Content-Type'] = 'application/json; charset=utf-8'
    res.body = JSON.generate({ 'channel' => 'feishu', 'result' => 'blocked', 'reason' => 'method_not_allowed' })
    next
  end

  payload = read_json_request(req)
  headers = read_headers(req)
  disabled = options[:disabled] || disabled_by_env? || config['webhook_enabled'] == false

  begin
    gate_stdout, _gate_stderr, gate_status = run_gate(
      payload,
      headers,
      options.merge(disabled: disabled)
    )
  rescue StandardError => e
    res.status = 500
    res['Content-Type'] = 'application/json; charset=utf-8'
    res.body = JSON.pretty_generate(
      'channel' => 'feishu',
      'result' => 'blocked',
      'reason' => 'server_error',
      'error' => "#{e.class}: #{e.message}",
      'worker_auto_dispatch_triggered' => false,
      'gateway_auto_dispatch_triggered' => false
    )
    next
  end

  parsed = JSON.parse(gate_stdout) rescue {}
  challenge = parsed.dig('reply_payload', 'challenge')

  if challenge
    res.status = 200
    res['Content-Type'] = 'application/json; charset=utf-8'
    res.body = JSON.generate({ 'challenge' => challenge })
  else
    code = gate_status&.exitstatus.to_i.zero? ? 200 : 400
    res.status = code
    res['Content-Type'] = 'application/json; charset=utf-8'
    res.body = gate_stdout.strip.empty? ? JSON.pretty_generate({ 'channel' => 'feishu', 'result' => 'blocked', 'reason' => 'empty_gate_response' }) : gate_stdout
  end
end

trap('INT') { server.shutdown }
trap('TERM') { server.shutdown }

server_thread = Thread.new { server.start }

if options[:ready_json]
  deadline = Time.now + 10
  loop do
    listener = server.listeners&.first
    port = listener&.addr&.[](1)
    break if port.to_i.positive?
    raise 'server_failed_to_bind' if Time.now >= deadline
    sleep 0.05
  end

  listener = server.listeners.first
  port = listener.addr[1]
  puts JSON.generate(
    ready_payload(
      port: port,
      webhook_path: webhook_path,
      healthz_path: healthz_path,
      readyz_path: readyz_path,
      disabled: options[:disabled] || disabled_by_env? || config['webhook_enabled'] == false,
      config_path: options[:config]
    )
  )
end

server_thread.join
