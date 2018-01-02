module FGT
  class RestApi
    #vpn ipsec
    %w[phase1 phase1_interface phase2 phase2_interface forticlient].each do |name|
      define_method('vpn_ipsec_' + name) do |vdom = use_vdom|
        cmdb_get(path: 'vpn.ipsec', name: name.tr('_', '-'), vdom: vdom).results
      end
    end
  end
end