module Aws
  module Plugins

    # @seahorse.client.option [required, Credentials] :credentials Your
    #   AWS credentials.  The following locations will be searched in order
    #   for credentials:
    #
    #   * `:access_key_id`, `:secret_access_key`, and `:session_token` options
    #   * ENV['AWS_ACCESS_KEY_ID'], ENV['AWS_SECRET_ACCESS_KEY']
    #   * `HOME/.aws/credentials` shared credentials file
    #   * EC2 instance profile credentials
    #
    # @seahorse.client.option [String] :profile Used when loading credentials
    #   from the shared credentials file at HOME/.aws/credentials.  When not
    #   specified, 'default' is used.
    #
    # @seahorse.client.option [String] :access_key_id Used to set credentials
    #   statically.
    #
    # @seahorse.client.option [String] :secret_access_key Used to set
    #   credentials statically.
    #
    # @seahorse.client.option [String] :session_token Used to set credentials
    #   statically.
    #
    class RequestSigner < Seahorse::Client::Plugin

      option(:access_key_id)

      option(:secret_access_key)

      option(:session_token)

      option(:profile)

      option(:credentials) do |config|
        CredentialProviderChain.new(config).resolve
      end

      # Intentionally not documented - this should go away when all
      # services support signature version 4 in every region.
      option(:signature_version) do |cfg|
        cfg.api.metadata['signatureVersion']
      end

      option(:sigv4_name) do |cfg|
        cfg.api.metadata['signingName'] || cfg.api.metadata['endpointPrefix']
      end

      option(:sigv4_region) do |cfg|
        prefix = cfg.api.metadata['endpointPrefix']
        endpoint = cfg.endpoint.to_s
        if matches = endpoint.match(/#{prefix}[.-](.+)\.amazonaws\.com/)
          matches[1] == 'us-gov' ? 'us-gov-west-1' : matches[1]
        elsif cfg.endpoint.to_s.match(/#{prefix}\.amazonaws\.com/)
          'us-east-1'
        else
          cfg.region
        end
      end

      class Handler < Seahorse::Client::Handler

        SIGNERS = {
          'v4'      => Signers::V4,
          'v3https' => Signers::V3,
          'v2'      => Signers::V2,
          's3'      => Signers::S3,
        }

        STS_UNSIGNED_REQUESTS = Set.new(%w(
          AssumeRoleWithSAML
          AssumeRoleWithWebIdentity
        ))

        COGNITO_IDENTITY_UNSIGNED_REQUESTS = Set.new(%w(
          GetCredentialsForIdentity
          GetId
          GetOpenIdToken
          ListIdentityPools
          UnlinkDeveloperIdentity
          UnlinkIdentity
        ))

        def call(context)
          sign_authenticated_requests(context) unless unsigned_request?(context)
          @handler.call(context)
        end

        private

        def sign_authenticated_requests(context)
          require_credentials(context)
          if signer = SIGNERS[context.config.signature_version]
            require_credentials(context)
            signer.sign(context)
          end
        end

        def require_credentials(context)
          if missing_credentials?(context)
            msg = 'unable to sign request without credentials set'
            raise Errors::MissingCredentialsError, msg
          end
        end

        def missing_credentials?(context)
          context.config.credentials.nil? or
          !context.config.credentials.set?
        end

        def unsigned_request?(context)
          if context.config.api.metadata['endpointPrefix'] == 'sts'
            STS_UNSIGNED_REQUESTS.include?(context.operation.name)
          elsif context.config.api.metadata['endpointPrefix'] == 'cloudsearchdomain'
            context.config.credentials.nil? || !context.config.credentials.set?
          elsif context.config.api.metadata['endpointPrefix'] == 'cognito-identity'
            COGNITO_IDENTITY_UNSIGNED_REQUESTS.include?(context.operation.name)
          else
            false
          end
        end

      end

      def add_handlers(handlers, config)
        # See the S3RequestSignerPlugin for Amazon S3 signature logic
        handlers.add(Handler, step: :sign) unless config.sigv4_name == 's3'
      end

    end
  end
end
