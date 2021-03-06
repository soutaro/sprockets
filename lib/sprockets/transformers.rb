require 'sprockets/utils'

module Sprockets
  module Transformers
    include Utils

    # Public: Two level mapping of a source mime type to a target mime type.
    #
    #   environment.transformers
    #   # => { 'text/coffeescript' => {
    #            'application/javascript' => ConvertCoffeeScriptToJavaScript
    #          }
    #        }
    #
    def transformers
      config[:transformers]
    end

    # Public: Two level mapping of target mime type to source mime type.
    #
    #   environment.inverted_transformers
    #   # => { 'application/javascript' => {
    #            'text/coffeescript' => ConvertCoffeeScriptToJavaScript
    #          }
    #        }
    #
    def inverted_transformers
      config[:inverted_transformers]
    end

    # Public: Register a transformer from and to a mime type.
    #
    # from - String mime type
    # to   - String mime type
    # proc - Callable block that accepts an input Hash.
    #
    # Examples
    #
    #   register_transformer 'text/coffeescript', 'application/javascript',
    #     ConvertCoffeeScriptToJavaScript
    #
    #   register_transformer 'image/svg+xml', 'image/png', ConvertSvgToPng
    #
    # Returns nothing.
    def register_transformer(from, to, proc)
      uri = build_processor_uri(:transformer, proc, from: from, to: to)
      register_processor_dependency_uri(uri, proc)

      self.config = hash_reassoc(config, :transformers, from) do |transformers|
        transformers.merge(to => proc)
      end
      self.config = hash_reassoc(config, :inverted_transformers, to) do |transformers|
        transformers.merge(from => proc)
      end
    end

    # Internal: Resolve target mime type that the source type should be
    # transformed to.
    #
    # type   - String from mime type
    # accept - String accept type list (default: '*/*')
    #
    # Examples
    #
    #   resolve_transform_type('text/plain', 'text/plain')
    #   # => 'text/plain'
    #
    #   resolve_transform_type('image/svg+xml', 'image/png, image/*')
    #   # => 'image/png'
    #
    #   resolve_transform_type('text/css', 'image/png')
    #   # => nil
    #
    # Returns String mime type or nil is no type satisfied the accept value.
    def resolve_transform_type(type, accept)
      find_best_mime_type_match(accept || '*/*', [type].compact + transformers[type].keys)
    end

    # Internal: Expand accept type list to include possible transformed types.
    #
    # parsed_accepts - Array of accept q values
    #
    # Examples
    #
    #   expand_transform_accepts([['application/javascript', 1.0]])
    #   # => [['application/javascript', 1.0], ['text/coffeescript', 0.8]]
    #
    # Returns an expanded Array of q values.
    def expand_transform_accepts(parsed_accepts)
      accepts = []
      parsed_accepts.each do |(type, q)|
        accepts.push([type, q])
        inverted_transformers[type].keys.each do |subtype|
          accepts.push([subtype, q * 0.8])
        end
      end
      accepts
    end
  end
end
