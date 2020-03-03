# frozen_string_literal: true

module FGT
  class RestApi
    def ssl_tunnels(tunnel_name = nil)
      options = tunnel_name.yield_self { |t| t.nil? ? {} : { tunnel: tunnel_name } }
      monitor_get('vpn/ssl/select', options).results.uniq
    end
  end
end
