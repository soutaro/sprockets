require 'sprockets/engines'
require 'sprockets/lazy_processor'
require 'sprockets/legacy_proc_processor'
require 'sprockets/legacy_tilt_processor'
require 'sprockets/mime'
require 'sprockets/uri_utils'
require 'sprockets/utils'

module Sprockets
  # `Processing` is an internal mixin whose public methods are exposed on
  # the `Environment` and `CachedEnvironment` classes.
  module Processing
    include URIUtils, Utils

    # Preprocessors are ran before Postprocessors and Engine
    # processors.
    def preprocessors
      config[:preprocessors]
    end

    # Postprocessors are ran after Preprocessors and Engine processors.
    def postprocessors
      config[:postprocessors]
    end

    # Registers a new Preprocessor `klass` for `mime_type`.
    #
    #     register_preprocessor 'text/css', Sprockets::DirectiveProcessor
    #
    # A block can be passed for to create a shorthand processor.
    #
    #     register_preprocessor 'text/css', :my_processor do |context, data|
    #       data.gsub(...)
    #     end
    #
    def register_preprocessor(*args, &block)
      register_config_processor(:preprocessors, *args, &block)
    end

    # Registers a new Postprocessor `klass` for `mime_type`.
    #
    #     register_postprocessor 'application/javascript', Sprockets::DirectiveProcessor
    #
    # A block can be passed for to create a shorthand processor.
    #
    #     register_postprocessor 'application/javascript', :my_processor do |context, data|
    #       data.gsub(...)
    #     end
    #
    def register_postprocessor(*args, &block)
      register_config_processor(:postprocessors, *args, &block)
    end

    # Remove Preprocessor `klass` for `mime_type`.
    #
    #     unregister_preprocessor 'text/css', Sprockets::DirectiveProcessor
    #
    def unregister_preprocessor(*args)
      unregister_config_processor(:preprocessors, *args)
    end

    # Remove Postprocessor `klass` for `mime_type`.
    #
    #     unregister_postprocessor 'text/css', Sprockets::DirectiveProcessor
    #
    def unregister_postprocessor(*args)
      unregister_config_processor(:postprocessors, *args)
    end

    # Bundle Processors are ran on concatenated assets rather than
    # individual files.
    def bundle_processors
      config[:bundle_processors]
    end

    # Registers a new Bundle Processor `klass` for `mime_type`.
    #
    #     register_bundle_processor  'application/javascript', Sprockets::DirectiveProcessor
    #
    # A block can be passed for to create a shorthand processor.
    #
    #     register_bundle_processor 'application/javascript', :my_processor do |context, data|
    #       data.gsub(...)
    #     end
    #
    def register_bundle_processor(*args, &block)
      register_config_processor(:bundle_processors, *args, &block)
    end

    # Remove Bundle Processor `klass` for `mime_type`.
    #
    #     unregister_bundle_processor 'application/javascript', Sprockets::DirectiveProcessor
    #
    def unregister_bundle_processor(*args)
      unregister_config_processor(:bundle_processors, *args)
    end

    # Internal: Two dimensional Hash of reducer functions for a given mime type
    # and asset metadata key.
    def bundle_reducers
      config[:bundle_reducers]
    end

    # Public: Register bundle metadata reducer function.
    #
    # Examples
    #
    #   Sprockets.register_bundle_metadata_reducer 'application/javascript', :jshint_errors, [], :+
    #
    #   Sprockets.register_bundle_metadata_reducer 'text/css', :selector_count, 0 { |total, count|
    #     total + count
    #   }
    #
    # mime_type - String MIME Type. Use '*/*' applies to all types.
    # key       - Symbol metadata key
    # initial   - Initial memo to pass to the reduce funciton (default: nil)
    # block     - Proc accepting the memo accumulator and current value
    #
    # Returns nothing.
    def register_bundle_metadata_reducer(mime_type, key, *args, &block)
      case args.size
      when 0
        reducer = block
      when 1
        if block_given?
          initial = args[0]
          reducer = block
        else
          initial = nil
          reducer = args[0].to_proc
        end
      when 2
        initial = args[0]
        reducer = args[1].to_proc
      else
        raise ArgumentError, "wrong number of arguments (#{args.size} for 0..2)"
      end

      self.config = hash_reassoc(config, :bundle_reducers, mime_type) do |reducers|
        reducers.merge(key => [initial, reducer])
      end
    end

    # Internal: Gather all bundle reducer functions for MIME type.
    #
    # mime_type - String MIME type
    #
    # Returns an Array of [initial, reducer_proc] pairs.
    def unwrap_bundle_reducers(mime_type)
      self.bundle_reducers['*/*'].merge(self.bundle_reducers[mime_type])
    end

    # Internal: Run bundle reducers on set of Assets producing a reduced
    # metadata Hash.
    #
    # assets - Array of Assets
    # reducers - Array of [initial, reducer_proc] pairs
    #
    # Returns reduced asset metadata Hash.
    def process_bundle_reducers(assets, reducers)
      initial = {}
      reducers.each do |k, (v, _)|
        initial[k] = v if v
      end

      assets.reduce(initial) do |h, asset|
        reducers.each do |k, (_, block)|
          value = k == :data ? asset.source : asset.metadata[k]
          h[k]  = h.key?(k) ? block.call(h[k], value) : value
        end
        h
      end
    end

    protected
      def resolve_processor_cache_key_uri(uri)
        return unless processor = config[:processor_dependency_uris][uri]
        processor = unwrap_processor(processor)
        processor.cache_key if processor.respond_to?(:cache_key)
      end

    private
      def register_config_processor(type, mime_type, klass, proc = nil, &block)
        proc ||= block

        processor = wrap_processor(klass, proc)

        pos = config[type][mime_type].size
        uri = build_processor_uri(type, processor, type: mime_type, pos: pos)
        register_processor_dependency_uri(uri, processor)

        self.config = hash_reassoc(config, type, mime_type) do |processors|
          processors.unshift(processor)
          processors
        end
      end

      def register_processor_dependency_uri(uri, processor)
        self.config = hash_reassoc(config, :processor_dependency_uris) do |uris|
          uris.merge(uri => processor)
        end
        self.config = hash_reassoc(config, :inverted_processor_dependency_uris) do |uris|
          uris.merge(processor => uri)
        end
      end

      def unregister_config_processor(type, mime_type, klass)
        if klass.is_a?(String) || klass.is_a?(Symbol)
          klass = config[type][mime_type].detect do |cls|
            cls.respond_to?(:name) && cls.name == "Sprockets::LegacyProcProcessor (#{klass})"
          end
        end

        self.config = hash_reassoc(config, type, mime_type) do |processors|
          processors.delete(klass)
          processors
        end
      end

      def wrap_processor(klass, proc)
        if !proc
          if klass.class == Sprockets::LazyProcessor || klass.respond_to?(:call)
            klass
          else
            LegacyTiltProcessor.new(klass)
          end
        elsif proc.respond_to?(:arity) && proc.arity == 2
          LegacyProcProcessor.new(klass.to_s, proc)
        else
          proc
        end
      end

      def unwrap_processors(processors)
        processors.map { |p| unwrap_processor(p) }
      end

      def unwrap_processor(processor)
        processor.respond_to?(:unwrap) ? processor.unwrap : processor
      end
  end
end
