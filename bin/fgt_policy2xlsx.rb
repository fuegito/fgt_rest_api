require 'optparse'
require 'axlsx'
require 'fgt_rest_api'
require 'fgt_rest_api/ext/all'

worksheets = %w[Policy AddressObjects AddressGroups VIPs VIPGroups IPPools Services ServiceGroups objectref]
################################################################################
################################################################################

options = {
  ip: 'fortigate.fortidemo.com',
  port: 443,
  use_vdom: 'root',
  username: 'demo',
  password: 'demo',
  safe_mode: true
}

parser = OptionParser.new do |opts|
  opts.banner = "Usage: policy2xlsx.rb [options]"

  opts.on('-f', '--fortigate fortigate', 'Hostname or IP address of FortiGate device.') do |fortigate|
    options[:ip] = fortigate
  end

  opts.on('-p', '--port port', 'HTTPS destination port of FGT REST API.') do |port|
    options[:port] = port.to_i
  end

  opts.on('-v', '--vdom vdom', 'VDOM name.') do |vdom|
    options[:use_vdom] = vdom
  end

  opts.on('-u', '--user user', 'User name for accessing FGT REST API.') do |user|
    options[:username] = user
  end

  opts.on('-s', '--secret secret', 'Secret/Password for FGT REST API user.') do |secret|
    options[:password] = secret
  end

  opts.on('-h', '--help', 'Displays Help') do
    puts opts
    exit
  end
end

parser.parse!

if options[:ip].nil?
  print 'Enter FortiGate Hostname or IP: '
  options[:ip] = STDIN.gets.chomp
end
if options[:port].nil?
  print 'Enter FortiGate port number: '
  options[:port] = STDIN.gets.chomp.to_i
end
if options[:use_vdom].nil?
  print 'Enter VDOM name: '
  options[:use_vdom] = STDIN.gets.chomp
end
if options[:username].nil?
  print 'Enter user name: '
  options[:username] = STDIN.gets.chomp
end
if options[:password].nil?
  print 'Enter secret/password: '
  options[:password] = STDIN.noecho(&:gets).chomp
end
################################################################################
################################################################################

timestamp = DateTime.now.strftime('%Y%m%d_%H-%M-%S')

STDERR.puts "Connecting to FortiGate '#{options[:ip]}' and retrieving config for VDOM '#{options[:use_vdom]}'..."
#rulebase = FGT::RestApi.new(ip: options[:ip], port: options[:port], username: options[:username], password: options[:password], use_vdom: options[:use_vdom])
rulebase = FGT::RestApi.new(options)
rulebase.timeout = 10
#Report_dir = ENV['HOME'] + '/REPORT/policy/'
#outfile_name = Report_dir + 'policy__' + server + '__' + vdom + '__' + timestamp + '.xlsx'
outfile_name = "policy__#{options[:ip]}__#{options[:use_vdom]}__#{timestamp}.xlsx"
################################################################################
################################################################################

def get_xlsx_columns(array = @headers)
  ('A'..'Z').to_a[0..(array.size-1)]
end

def add_obj_xlsxreference(o)
  @cells[o.name][:hyperlink] = '"#' + @sheet.name + '!$A$' + @cell.y.to_s + '"'
  @cells[o.name][:cell] = @sheet.name + '!$A$' + @cell.y.to_s
end

def xlsx_hyperlink(target, linktext)
  "=hyperlink(#{target},\"#{linktext.to_s[0..254]}\")"
end

def add_row(
  object: nil,
  styles: set_alt_styles * (@columns.size / 2),
  types: @columns.size.times.map { :string },
  row: nil,
  widths: [:auto] * @headers.size
)
  add_obj_xlsxreference(object) unless object.nil?
  @cell.y_incr
  return @sheet.ws.add_row(@headers, styles: styles, types: types, widths: widths) if row.nil?
  @sheet.ws.add_row(row, styles: styles, types: types, widths: widths)
end

def set_alt_styles
  if (@cell.y % 2).zero?
    [@style[:obj_data_firstrow_color1], @style[:obj_data_rows_color1]]
  else
    [@style[:obj_data_firstrow_color2], @style[:obj_data_rows_color2]]
  end
end

def auto_filter
  @sheet.ws.auto_filter = "A1:A#{@cell.y - 1}"
end

def fixed_top_row(pane)
  pane.top_left_cell = 'B2'
  pane.state = :frozen_split
  pane.y_split = 1
  pane.x_split = 0
  pane.active_pane = :bottom_right
end

def fix_top_row
  @sheet.ws.sheet_view.pane(&method(:fixed_top_row))
end

def create_ws_groups(obj_base, max_members)
  @headers = ["name", ("members " * max_members).split(/\s/)].flatten
  (@headers.size - 1).times { @cell.x_incr }
  @columns = get_xlsx_columns
  add_row(styles: [@style[:header]]*@columns.size)
  obj_base.each do |o|
    members = Array.new
    o.member.each do |m|
      members << xlsx_hyperlink(@cells[m.name][:hyperlink], m.name)
    end
    my_style = [set_alt_styles[0]]
    members.size.times { my_style << set_alt_styles[1] }
    my_width = [32] * (members.size + 1)
    add_row(object: o, row: Array(o.name) + members, styles: my_style, widths: my_width)
  end
end
################################################################################
################################################################################

# cell pointer
@cell = Struct.new(:x, :y) do
  def initialize(x = 'A', y = 1)
    super
  end

  def x_incr
    self.x = self.x.next
  end

  def y_incr
    self.y = self.y.next
  end

  def reset
    self.y = 1
    self.x = 'A'
  end
end.new

# hash for collecting object references in xlsx
@cells = Hash.new { |hsh, key| hsh[key] = Hash.new }

# hash for xlsx styles
@style = Hash.new

# struct for sheet
Sheet = Struct.new(:name, :ws)
################################################################################
################################################################################

p = Axlsx::Package.new
p.workbook do |wb|
  # define styles
  @style[:font_8] = wb.styles.add_style(sz: 8, alignment: { horizontal: :left })
  @style[:bottom_thick_line] = wb.styles.add_style(sz: 8, b: true, border: { style: :thick, color: "FFFF0000", edges: [:bottom] }, alignment: { horizontal: :left })
  @style[:wrap_text] = wb.styles.add_style(sz: 8, alignment: { wrap_text: true, horizontal: :left })
  @style[:obj_data_rows_color1] = wb.styles.add_style(sz: 8, border: Axlsx::STYLE_THIN_BORDER, bg_color: 'DBE5F1', alignment: { wrap_text: true })
  @style[:obj_data_firstrow_color1] = wb.styles.add_style(sz: 8, border: Axlsx::STYLE_THIN_BORDER, bg_color: 'DBE5F1', b: true, alignment: { wrap_text: true })
  @style[:obj_data_rows_color2] = wb.styles.add_style(sz: 8, border: Axlsx::STYLE_THIN_BORDER, bg_color: 'EAF1DD', alignment: { wrap_text: true })
  @style[:obj_data_firstrow_color2] = wb.styles.add_style(sz: 8, border: Axlsx::STYLE_THIN_BORDER, bg_color: 'EAF1DD', b: true, alignment: { wrap_text: true })
  @style[:header] = wb.styles.add_style(bg_color: '00', fg_color: 'FF', b: true)

  # create worksheets
  # create policy ws first but put it at last place for processing
  worksheets = worksheets.map { |ws| Sheet.new(ws, wb.add_worksheet(name: ws)) }.rotate

  # addresses (range, host, network, fqdn)
  @cell.reset
  @sheet = worksheets.find { |ws| ws.name == 'AddressObjects' }
  @headers = ["name", "type", "address/start-ip/fqdn", "netmask/end-ip/wildcard-fqdn"]
  (@headers.size - 1).times { @cell.x_incr }
  @columns = get_xlsx_columns
  add_row(styles: [@style[:header]]*@columns.size)
  (rulebase.ipaddress + rulebase.ipnetwork).each do |o|
    add_row(object: o, row: [o.name, o.type, *o.subnet.split(/\s/)])
  end
  rulebase.iprange.each do |o|
    add_row(object: o, row: [o.name, o.type, o.start_ip, o.end_ip])
  end
  (rulebase.fqdn + rulebase.wildcard_fqdn).each do |o|
    add_row(object: o, row: [o.name, o.type, o.fqdn, o.wildcard_fqdn])
  end
  fix_top_row
  auto_filter

  # address groups
  max_members = 0
  rulebase.addrgrp.each { |o| max_members = o.member.size if o.member.size > max_members }
  @cell.reset
  @sheet = worksheets.find { |ws| ws.name == 'AddressGroups' }
  create_ws_groups(rulebase.addrgrp, max_members)

  # VIPs (LB & DNAT)
  @cell.reset
  @sheet = worksheets.find { |ws| ws.name == 'VIPs' }
  @headers = ["name", "type", "address"]
  (@headers.size - 1).times { @cell.x_incr }
  @columns = get_xlsx_columns
  add_row(styles: [@style[:header]]*@columns.size)
  rulebase.vip.each do |o|
    add_row(object: o, row: [o.name, o.type, o.extip])
  end
  fix_top_row
  auto_filter

  # VIP groups
  max_members = 0
  rulebase.vipgrp.each { |o| max_members = o.member.size if o.member.size > max_members }
  @cell.reset
  @sheet = worksheets.find { |ws| ws.name == 'VIPGroups' }
  create_ws_groups(rulebase.vipgrp, max_members)

  # IPpools (SNAT)
  @cell.reset
  @sheet = worksheets.find { |ws| ws.name == 'IPPools' }
  @headers = ["name", "type", "start-ip", "end-ip"]
  (@headers.size - 1).times { @cell.x_incr }
  @columns = get_xlsx_columns
  add_row(styles: [@style[:header]]*@columns.size)
  rulebase.ippool.each do |o|
    add_row(object: o, row: [o.name, o.type, o.startip, o.endip])
  end
  fix_top_row
  auto_filter

  # services
  @cell.reset
  @sheet = worksheets.find { |ws| ws.name == 'Services' }
  @headers = ["name", "protocols", "tcp-ports", "udp-ports", "icmp-type", "icmp-code"]
  (@headers.size - 1).times { @cell.x_incr }
  @columns = get_xlsx_columns
  add_row(styles: [@style[:header]]*@columns.size)
  rulebase.service_custom.each do |o|
    add_row(object: o, row: [o.name, o.protocol, o.tcp_portrange, o.udp_portrange, o.icmptype, o.icmpcode])
  end
  fix_top_row
  auto_filter

  # service groups
  max_members = 0
  rulebase.service_group.each { |o| max_members = o.member.size if o.member.size > max_members }
  @cell.reset
  @sheet = worksheets.find { |ws| ws.name == 'ServiceGroups' }
  create_ws_groups(rulebase.service_group, max_members)

  # objectref worksheet
  @cell.reset
  @sheet = worksheets.find { |ws| ws.name == 'objectref' }
  @headers = [''] * 3
  (@headers.size - 1).times { @cell.x_incr }
  @columns = get_xlsx_columns
  add_row(styles: [@style[:header]]*@columns.size)
  rulebase.policy.each do |o|
    @cells[:policy][o.policyid] = Hash.new
    @cells[:policy][o.policyid][:src_hyperlink] = '"#' + @sheet.name + '!$A$' + @cell.y.to_s + '"'
    @cells[:policy][o.policyid][:src_cell] = @sheet.name + '!$A$' + @cell.y.to_s
    add_row(row: ["rule id ##{o.policyid}", 'srcaddr', 'objects'], styles: [@style[:header]]*@columns.size)
    o.srcaddr.each do |src|
      add_row(row: ['', '', xlsx_hyperlink(@cells[src.name][:hyperlink], src.name)])
    end
    @cells[:policy][o.policyid][:dst_hyperlink] = '"#' + @sheet.name + '!$A$' + @cell.y.to_s + '"'
    @cells[:policy][o.policyid][:dst_cell] = @sheet.name + '!$A$' + @cell.y.to_s
    add_row(row: ["rule id ##{o.policyid}", 'dstaddr', 'objects'], styles: [@style[:header]]*@columns.size)
    o.dstaddr.each do |dst|
      add_row(row: ['', '', xlsx_hyperlink(@cells[dst.name][:hyperlink], dst.name)])
    end
    @cells[:policy][o.policyid][:svc_hyperlink] = '"#' + @sheet.name + '!$A$' + @cell.y.to_s + '"'
    @cells[:policy][o.policyid][:svc_cell] = @sheet.name + '!$A$' + @cell.y.to_s
    add_row(row: ["rule id ##{o.policyid}", 'service', 'objects'], styles: [@style[:header]]*@columns.size)
    o.service.each do |svc|
      add_row(row: ['', '', xlsx_hyperlink(@cells[svc.name][:hyperlink], svc.name)])
    end
    2.times { add_row(styles: [@style[:header]]*@columns.size) }
  end

  # policy
  @cell.reset
  @sheet = worksheets.find { |ws| ws.name == 'Policy' }
  @headers = ["rule #ID", "status", "sequence", "folder", "source", "destination", "schedule", "service", "action"]
  (@headers.size - 1).times { @cell.x_incr }
  @columns = get_xlsx_columns
  add_row(styles: [@style[:header]]*@columns.size)
  rulebase.policy.each_with_index do |o,i|
    add_row(
      row: [
        o.policyid,
        o.status,
        (i+1).to_s,
        o.global_label,
        xlsx_hyperlink(@cells[:policy][o.policyid][:src_hyperlink], o.srcaddr.map(&:name).join("\n")),
        xlsx_hyperlink(@cells[:policy][o.policyid][:dst_hyperlink], o.dstaddr.map(&:name).join("\n")),
        o.schedule,
        xlsx_hyperlink(@cells[:policy][o.policyid][:svc_hyperlink], o.service.map(&:name).join("\n")),
        o.action
      ]
    )
  end
  fix_top_row
  auto_filter

  # write file
  p.serialize(outfile_name)
  STDERR.puts "Excel policy written to file: '#{outfile_name}'..."
end

print File.absolute_path(outfile_name)