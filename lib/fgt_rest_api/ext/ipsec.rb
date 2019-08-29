# frozen_string_literal: true

module FGT
  class RestApi
    %w[phase1 phase1_interface phase2 phase2_interface forticlient].each do |name|
      define_method('vpn_ipsec_' + name) do |vdom = use_vdom|
        cmdb_get(path: 'vpn.ipsec', name: name.tr('_', '-'), vdom: vdom).results
      end
    end

    def ipsec_tunnels(tunnel_name = nil)
      options = tunnel_name.yield_self { |t| t.nil? ? {} : { tunnel: tunnel_name } }
      monitor_get('vpn/ipsec', options).results.uniq
    end

    def ipsec_tunnel_names
       ipsec_tunnels.select { |t1| t1['parent'].nil? }.map { |t| t['name'] }
    end

    def ipsec_tunnel_children
       ipsec_tunnels.select { |t1| not(t1['parent'].nil?) }.map { |t| t['name'] }
    end

    def ipsec_incoming_bytes(tunnel_parent)
       ipsec_tunnels.select { |t| t['parent'] == tunnel_parent || t['name'] == tunnel_parent }.map { |t2| t2['incoming_bytes'] }.inject(0) { |sum, x| sum + x }
    end

    def ipsec_outgoing_bytes(tunnel_parent)
       ipsec_tunnels.select { |t| t['parent'] == tunnel_parent || t['name'] == tunnel_parent }.map { |t2| t2['outgoing_bytes'] }.inject(0) { |sum, x| sum + x }
    end
  end
end
