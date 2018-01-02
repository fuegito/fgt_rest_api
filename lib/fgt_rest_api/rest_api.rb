module FGT
  class RestApi
    class << self
      def tcp_port_open?(ip, port, timeout = 2)
        Timeout.timeout(timeout) do
          TCPSocket.new(ip, port).close
          true
        end
      rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH,
             Errno::ETIMEDOUT, Timeout::Error
        return false
      end
    end

    attr_reader(
      :proxy, :use_proxy,
      :url_schema, :inst_var_refreshable
    )

    attr_accessor(
      :api_version, :ip, :port,
      :username, :secretkey, :timeout,
      :ccsrftoken, :client, :debug,
      :safe_mode, :use_vdom, :retry_counter
    )

    def initialize(
      api_version: 'v2',
      url_schema: 'https',
      ip:,
      port: 443,
      username:,
      password:,
      timeout: 5,
      proxy: ENV['http_proxy'],
      use_proxy: false,
      debug: false,
      safe_mode: true,
      retry_counter: 3,
      use_vdom: 'root'
    )
      self.url_schema = url_schema
      self.use_vdom = use_vdom
      self.safe_mode = safe_mode
      self.debug = debug
      self.timeout = timeout
      self.api_version = api_version
      self.ip = ip
      self.port = port
      self.proxy = proxy
      self.use_proxy = use_proxy
      self.client = new_httpclient
      self.username = username
      self.secretkey = password
      self.ccsrftoken = String.new
      self.retry_counter = retry_counter
    end

    def use_proxy=(boolean)
      @use_proxy = !!boolean
      self.client = new_httpclient
    end

    def proxy=(pxy)
      @proxy = pxy
      self.client = new_httpclient if use_proxy
      proxy
    end

    %w[get post].each do |request_method|
      define_method('monitor_' + request_method) do |path, params = {}|
        raise(SafeModeActiveError) if (request_method != 'get' && safe_mode)
        path.gsub!(/\/*$/, '')
        url_path = "api/#{api_version}/monitor/#{path}/"
        params[:vdom] = use_vdom unless params.key?(:vdom)
        request(request_method, url_path, params)
      end
    end

    %w[get post put delete].each do |request_method|
      define_method('cmdb_' + request_method) do |args_hash|
        args_hash[:request_method] = request_method
        cmdb(args_hash)
      end
    end

    private

    # memoize db/cache results in instance variable dynamically
    def memoize_results(key)
      (@inst_var_refreshable || @inst_var_refreshable = Set.new) << key
      return instance_variable_get(key) if instance_variable_defined?(key)
      instance_variable_set(key, yield)
    end

    def url_schema=(schema)
      @url_schema = (schema == 'http' ? 'http' : 'https')
    end

    def https?
      url_schema == 'https'
    end

    def new_httpclient
      unless use_proxy
        ENV['http_proxy'] = ''
        raise FGTPortNotOpenError unless self.class.tcp_port_open?(ip, port, timeout)
      else
        ENV['http_proxy'] = proxy
      end
      client = HTTPClient.new(nil)
      client.set_cookie_store('/dev/null')
      client.ssl_config.verify_mode = OpenSSL::SSL::VERIFY_NONE if https?
      client
    end

    def cmdb(request_method: 'get', path:, name:, mkey: '', child_name: '', child_mkey: '', vdom: use_vdom, params: {})
      raise(SafeModeActiveError) if (request_method != 'get' && safe_mode)
      raise(CMDBPathError) unless /^\w*\.?\w+$/ === path
      raise(CMDBNameError) unless /^[^\/]+$/ === name
      raise(CMDBMKeyError) unless /^[^\/]*$/ === mkey
      raise(CMDBChildNameError) unless /^[^\/]*$/ === child_name
      raise(CMDBChildMKeyError) unless /^[^\/]*$/ === child_mkey
      url_path = "api/#{api_version}/cmdb/#{path}/#{name}/"
      unless mkey.empty?
        url_path += "#{mkey}/"
        unless child_name.empty?
          url_path += "#{child_name}/"
          unless child_mkey.empty?
            url_path += "#{child_mkey}/"
          end
        end
      end
      url_path += "?vdom=#{vdom}" if %w( put delete ).include?(request_method)
      params[:vdom] = vdom if %w( post get ).include?(request_method)
      request(request_method, url_path, params)
    end

    def request(method, path, params = {})
      retries ||= retry_counter
      url = "#{url_schema}://#{ip}:#{port}/#{path}"
      Timeout.timeout(timeout) do
        begin
          login
          if method == 'get'
            response = client.get(url, params)
          elsif method == 'post'
            response = client.post(url, params.to_json, 'X-CSRFTOKEN' => ccsrftoken)
          elsif method == 'put'
            response = client.put(url, body: params.to_json, header: {'X-CSRFTOKEN' => ccsrftoken})
          elsif method == 'delete'
            response = client.delete(url, query: params, header: {'X-CSRFTOKEN' => ccsrftoken})
          else
            raise HTTPMethodUnknownError
          end
          JSON.parse(response.body.encode('UTF-8', 'binary', invalid: :replace, undef: :replace, replace: ''), object_class: FGT::FCHash)
        rescue JSON::ParserError => e
          STDERR.puts "#{e.inspect} => #{e.backtrace}" if debug
          STDERR.puts "response_body: #{response.body}" if debug
          (retries -= 1) > 0 ? retry : raise # TooManyRetriesError
        rescue SocketError => e
          STDERR.puts "SocketError: #{e.inspect} => #{e.backtrace}" if debug
          (retries -= 1) > 0 ? retry : raise # TooManyRetriesError
        ensure
          logout
        end
      end
    end

    def login
      retries ||= retry_counter
      Timeout.timeout(timeout) do
        begin
          url = "https://#{ip}:#{port}/logincheck"
          params = { username: username, secretkey: secretkey }
          client.post(url, params)
        rescue SocketError => e
          STDERR.puts('#login: ' + e.inspect) if debug
          (retries -= 1) > 0 ? retry : raise # TooManyRetriesError
        rescue JSON::ParserError => e
          STDERR.puts('#login post: JSON::ParserError' + e.inspect) if debug
          (retries -= 1) > 0 ? retry : raise # TooManyRetriesError
        end
        self.ccsrftoken = client.cookies.find { |c| c.name == 'ccsrftoken' }
      end
    end

    def logout
      retries = retry_counter
      Timeout.timeout(@timeout) do
        begin
          url = "https://#{@ip}:#{@port}/logout"
          client.get(url)
        rescue SocketError => e
          STDERR.puts('#logout: ' + e.inspect) if debug
          (retries -= 1) > 0 ? retry : raise # TooManyRetriesError
        end
        client.cookies.clear
      end
    end
  end
end