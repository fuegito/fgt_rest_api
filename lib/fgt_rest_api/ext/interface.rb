module FGT
  class RestApi
    def interface_by_name(interface, vdom = use_vdom)
      cmdb_get(path: 'system', name: 'interface', vdom: vdom, params: { filter: ["name==#{interface}", "vdom==#{vdom}"] }).results.find do |i|
        i.vdom == vdom && i.name == interface
      end
    end

    # Interface types: %w[vlan physical aggregate tunnel]
    def interface(vdom = use_vdom, *interface_types)
      interface_types = %w[vlan physical aggregate tunnel] if interface_types.empty?
      cmdb_get(path: 'system', name: 'interface', vdom: vdom, params: { filter: "vdom==#{vdom}" }).results.select do |n|
        interface_types.include?(n.type) && n.vdom == vdom
      end
    end
  end
end