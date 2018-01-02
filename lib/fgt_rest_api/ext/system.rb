module FGT
  class RestApi
    def vdoms
      cmdb_get(path: 'system', name: 'vdom').results.map(&:name)
    end

    def hostname
      cmdb_get(path: 'system', name: 'global').results.hostname
    end
  end
end