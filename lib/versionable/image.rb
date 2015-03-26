require 'json'
module Versionable
  class Image
    class InvalidMetadata < StandardError; end

    attr_reader :width, :height
    def initialize(model, column, accessor, &blk)
      @model = model
      @column = column
      @accessor = accessor
      @versions = {}

      instance_eval(&blk) if block_given?
    end

    def url(*args)

      if (version_key = args.first) && versions.has_key?(version_key)
        versions[version_key].url
      else
        [Versionable.config.thumbor_server,signed_path('')].join('/')
      end
    end

    def to_s
      model.send(column)
    end

    def store_path
      model.send(column)
    end

    def respond_to?(method, include_private = false)
      super || @versions.key?(method)
    end

    def to_json(_options = nil)
      JSON.generate(as_json)
    end

    def as_json(_options = nil)
      serializable_hash
    end

    def fetch_metadata
      metadata_url = URI.parse(Versionable::Version.new(self, meta: true).url)
      json_data = Net::HTTP.get(metadata_url)
      object_is_blank?(json_data) ? nil : JSON.parse(Net::HTTP.get(metadata_url))
    end

    def height_from_metadata(hash)
      @height = hash['thumbor']['source']['height']
    rescue
      raise InvalidMetadata,
            'Argument is not valid thumbor metadata. " +
            "Use #fetch_metadata to get it.'
    end

    def width_from_metadata(hash)
      @width = hash['thumbor']['source']['width']
    rescue
      raise InvalidMetadata,
            'Argument is not valid thumbor metadata. " +
            "Use #fetch_metadata to get it.'
    end

    def decoded_url
      URI.decode(store_path).gsub(/[+ ]/, '%20')
      # We need gsub to change '+' to ' ' when the url is decoded,
      # but it doesn't, so we karate-chop 'em into place.
    end


    private

    attr_reader :model, :column, :accessor, :versions

    def method_missing(name, *args, &blk)
      if versions.respond_to?(:key?) && versions.key?(name)
        versions[name]
      else
        super
      end
    end

    def version(name, options, &blk)
      @versions[name] = Versionable::Version.new(self, options, &blk)
    end

    def object_is_blank?(obj)
      obj.respond_to?(:empty?) ? !!obj.empty? : !obj
    end

    def serializable_hash(_options = nil)
      # TODO: Add serializable_attributes to Version,
      # so that we dont hardcode url as the only attribute that gets serialized.
      { 'url' => url }.merge Hash[@versions.map do |name, version|
        [name, { 'url' => version.url }]
      end]
    end

    def signed_path options_url
      key =  Versionable.config.secret_key
      path = [options_url,decoded_url].join('/')
      [Base64.urlsafe_encode64(OpenSSL::HMAC.digest('sha1', key, path)),path].join('/')
    end

  end
end
