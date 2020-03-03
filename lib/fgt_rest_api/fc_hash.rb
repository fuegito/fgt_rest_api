# frozen_string_literal: true

module FGT
  class FCHash < ::Hash
    def []=(key, value)
      raise(ArgumentError, "key needs start with downcase letter: >>#{key}<<") unless key[0] == key[0].downcase
      if key.is_a?(String)
        super(key, value)
      elsif key.is_a?(Symbol)
        super(key.to_s.tr('_', '-'), value)
      else
        raise(ArgumentError, "'key needs to be a string and key needs start with downcase letter: >>#{key.inspect}<<") unless key.is_a?(String)
      end
      attribute_methods(key, value)
    end

    def [](key)
      raise(ArgumentError, "key needs start with downcase: >>#{key}<<") unless key.to_s[0] == key.to_s[0].downcase
      if key.is_a?(String)
        super(key)
      elsif key.is_a?(Symbol)
        super(key.to_s) || super(key.to_s.tr('_', '-'))
      else
        raise(ArgumentError, "'key needs to be a string and key needs start with downcase letter: >>#{key.inspect}<<") unless key.is_a?(String)
      end
    end

    def method_missing(m, *args, &block)
      nil
    end

    private

    def attribute_methods(key, value)
      getter_method(key)
      setter_method(key)
      value
    end

    def getter_method(key)
      method_name = key.to_s.tr('-', '_')
      return true if respond_to?(method_name.to_sym)
      define_singleton_method(method_name) do
        begin
          fetch(key)
        rescue KeyError
          fetch(key.to_s)
        end
      end
    end

    def setter_method(key)
      method_name = key.to_s.tr('-', '_') + '='
      return true if respond_to?(method_name.to_sym)
      define_singleton_method(method_name) { |v| store(key, v) }
    end
  end
end
