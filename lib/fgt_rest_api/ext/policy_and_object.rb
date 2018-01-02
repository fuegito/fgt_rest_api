module FGT
  class RestApi
    %w[address addrgrp vip vipgrp policy ippool].each do |name|
      define_method(name) do |vdom = use_vdom|
        memoize_results("@#{name}_response") do
          cmdb_get(path: 'firewall', name: name, vdom: vdom).results
        end
      end
    end

    %w[custom group].each do |name|
      define_method('service_' + name) do |vdom = use_vdom|
        memoize_results("@#{name}_response") do
          cmdb_get(path: 'firewall.service', name: name, vdom: vdom).results
        end
      end
    end

    def clear_cache_var(ivar)
      return nil unless instance_variable_defined?(ivar) && @inst_var_refreshable.include?(ivar)
      remove_instance_variable(ivar)
      @inst_var_refreshable.tap { |a| a.delete(ivar) }
    end

    def clear_cache(ivar = nil)
      ivar.nil? ? @inst_var_refreshable.each(&method(:clear_cache_var)) : clear_cache_var(ivar)
    end

    def policy_object(object_name: nil, vdom: use_vdom)
      if object_name.nil?
        address(vdom) + addrgrp(vdom) + vip(vdom) + vipgrp(vdom) + ippool(vdom)
      else
        (address(vdom) + addrgrp(vdom) + vip(vdom) + vipgrp(vdom) + ippool(vdom)).find { |o| o.name == object_name }
      end
    end

    def find_address_object_by_name(name, vdom = use_vdom)
      policy_object(object_name: name, vdom: vdom)
    end

    def service_object(vdom = use_vdom)
      service_custom(vdom) + service_group(vdom)
    end

    def iprange(vdom = use_vdom)
      address(vdom).select { |o| o.type == 'iprange' }
    end

    def vip_loadbalancer(vdom = use_vdom)
      vip(vdom).select { |o| o.type == 'server-load-balance' }
    end

    def vip_dnat(vdom = use_vdom)
      vip(vdom).select { |o| o.type == 'static-nat' }
    end

    def ipaddress(vdom = use_vdom)
      address(vdom).select { |o| o.type == 'ipmask' && /255.255.255.255$/.match(o.subnet) }
    end

    def ipnetwork(vdom = use_vdom)
      address(vdom).select { |o| o.type == 'ipmask' && !/255.255.255.255$/.match(o.subnet) }
    end

    def fqdn(vdom = use_vdom)
      address(vdom).select { |o| o.type == 'fqdn' }
    end

    def wildcard_fqdn(vdom = use_vdom)
      address(vdom).select { |o| o.type == 'wildcard-fqdn' }
    end

    def find_group_for_object(object, vdom = use_vdom)
      groups = (vipgrp(vdom) + addrgrp(vdom)).select { |o| o.member.map(&:q_origin_key).include?(object) }
      groups.each do |group|
        grouped_groups = find_group_for_object(group[:name], vdom)
        next if grouped_groups.empty?
        groups += grouped_groups
      end
      groups.flatten.uniq.compact
    end

    def find_address_object_by_address(addr, vdom = use_vdom)
      addr = NetAddr::CIDR.create(addr)
      address(vdom).select do |o|
        if o.type == 'ipmask'
          NetAddr::CIDR.create(o.subnet).contains?(addr) || (NetAddr::CIDR.create(o.subnet) == addr)
        elsif o.type == 'iprange'
          (NetAddr::CIDR.create(o.start_ip)..NetAddr::CIDR.create(o.end_ip)).cover?(addr)
        elsif /^\s*(?:wildcard(?:_|-))?fqdn\s*$/ === o.type
          next
        # TODO: add more types, maybe?
        else
          raise(FGTAddressTypeError, "this is neither an iprange nor an ipmask: #{o.inspect}")
        end
      end.uniq
    end

    def find_vip_object_by_address(addr, vdom = use_vdom)
      addr = NetAddr::CIDR.create(addr)
      vip(vdom).select do |o|
        begin
          (
            NetAddr::CIDR.create(o.extip) == addr
          ) ||
            (
              if o.type == 'static-nat'
                o.mappedip.find do |m|
                  begin
                    NetAddr::CIDR.create(m.range).contains?(addr) || NetAddr::CIDR.create(m.range) == addr
                  rescue NetAddr::ValidationError
                    (NetAddr::CIDR.create(m.range.split(/\s+|-/)[0])..NetAddr::CIDR.create(m.range.split(/\s+|-/)[1])).cover?(addr)
                  end
                end
              elsif o.type == 'server-load-balance'
                o.realservers.find { |r| NetAddr::CIDR.create(r.ip) == addr }
              else
                raise(FGTVIPTypeError, "this is neither a static-nat nor a server-load-balance type: #{o.inspect}")
              end
            )
        # TODO: get more specific here...
        rescue ArgumentError
          puts o.inspect
          raise
        end
      end.uniq
    end

    def find_ippool_object_by_address(addr, vdom = use_vdom)
      addr = NetAddr::CIDR.create(addr)
      ippool(vdom).select do |o|
        (NetAddr::CIDR.create(o.startip)..NetAddr::CIDR.create(o.endip)).cover?(addr) ||
          (NetAddr::CIDR.create(o.source_startip)..NetAddr::CIDR.create(o.source_endip)).include?(addr)
      end.uniq
    end

    def find_object_by_address(addr, vdom = use_vdom)
      objects = find_address_object_by_address(addr, vdom) + find_vip_object_by_address(addr, vdom) + find_ippool_object_by_address(addr, vdom)
      objects << objects.map { |o| find_group_for_object(o.name) }.uniq.flatten
      objects.flatten.uniq.compact
    end

    def find_src_policy_for_object(object, vdom = use_vdom)
      objects = Array.new
      rules = Array.new
      objects << policy_object(object_name: object, vdom: vdom)
      objects << find_group_for_object(object, vdom)
      objects.flatten.compact.uniq.each do |o|
        rules << policy(vdom).select do |p|
          (p.srcaddr.map(&:q_origin_key).include? o.name) ||
            (p.poolname.map(&:q_origin_key).nil? ? false : (p.poolname.map(&:q_origin_key).include? o.name))
        end
      end
      rules.flatten.uniq.compact
    end

    def find_dst_policy_for_object(object, vdom = use_vdom)
      objects = Array.new
      rules = Array.new
      objects << policy_object(object_name: object, vdom: vdom)
      objects << find_group_for_object(object, vdom)
      objects.flatten.compact.uniq.each do |o|
        rules << policy(vdom).select do |p|
          (p.dstaddr.map(&:q_origin_key).include? o.name)
        end
      end
      rules.flatten.uniq.compact
    end

    def find_policy_for_object(object, vdom = use_vdom)
      (find_src_policy_for_object(object, vdom) + find_dst_policy_for_object(object, vdom)).flatten.uniq
    end

    def find_src_policy_for_address(addr, vdom = use_vdom)
      find_object_by_address(addr, vdom).map { |o| find_src_policy_for_object(o.name, vdom) }.flatten.uniq
    end

    def find_dst_policy_for_address(addr, vdom = use_vdom)
      find_object_by_address(addr, vdom).map { |o| find_dst_policy_for_object(o.name, vdom) }.flatten.uniq
    end

    def find_policy_for_address(addr, vdom = use_vdom)
      find_object_by_address(addr, vdom).map { |o| find_policy_for_object(o.name, vdom) }.flatten.uniq
    end

    def search_object(*object_re, vdom: use_vdom, comment: false)
      object_re = Array(object_re).map { |re| re.is_a?(Regexp) ? re : Regexp.new(re.gsub(/\./, '\.')) }
      object_re = Regexp.union(object_re)
      with_name = ->(o) { object_re === o.name }
      with_name_and_comment = ->(o) { (object_re === o.name) || (object_re === o.comment) }
      search = comment ? with_name_and_comment : with_name
      with_groups = ->(o) { [o] << find_group_for_object(o.name, vdom) }
      policy_object.select(&search).map(&with_groups).flatten.uniq.compact
    end
  end
end
