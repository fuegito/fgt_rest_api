module FGT
  class RestApi
    %w[static policy ospf bgp isis rip].each do |name|
      define_method('router_' + name) do |vdom = use_vdom|
        cmdb_get(path: 'router', name: name, vdom: vdom).results
      end
    end
  end
end