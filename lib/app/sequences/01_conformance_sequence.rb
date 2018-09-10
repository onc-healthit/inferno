module Inferno
  module Sequence
    class ConformanceSequence < SequenceBase

      group 'Discovery'

      title 'Conformance Statement'

      description 'Verify that the FHIR server exposes a Conformance Statement with the necessary information.'

      test_id_prefix 'C'

      requires :url
      defines :oauth_authorize_endpoint, :oauth_token_endpoint, :oauth_register_endpoint

      test '01', '', 'FHIR server secured by transport layer security',
           'https://www.hl7.org/fhir/security.html',
           'All exchange of production data should be secured with TLS/SSL.',
           :optional do

        skip 'TLS tests have been disabled by configuration.' if @disable_tls_tests
        assert_tls_1_2 @instance.url
        warning {
          assert_deny_previous_tls @instance.url
        }
      end

      test '02', '', 'FHIR server responds to /metadata endpoint with valid DSTU2 Conformance Statement resource',
           'https://www.hl7.org/fhir/DSTU2/http.html',
           'Servers shall provide a conformance statement that specifies which interactions and resources are supported.' do

        @conformance = @client.conformance_statement(FHIR::Formats::ResourceFormat::RESOURCE_JSON_DSTU2)
        assert_response_ok @client.reply
        assert @conformance.class == FHIR::DSTU2::Conformance, 'Expected valid DSTU2 Conformance resource.'
      end

      test '03', '', 'Conformance Statement states JSON support',
           'http://www.fhir.org/guides/argonaut/r2/Conformance-server.html',
           'The Argonaut Data Query Server shall support JSON resource format for all Argonaut Data Query interactions.' do
        assert @conformance.class == FHIR::DSTU2::Conformance, 'Expected valid DSTU2 Conformance resource'
        assert @conformance.format.include?('json') || @conformance.format.include?('application/json+fhir'), 'Conformance does not state support for json.'
      end

      test '04', '', 'Conformance Statement provides OAuth 2.0 endpoints',
           'http://www.hl7.org/fhir/smart-app-launch/capability-statement/',
           'If a server requires SMART on FHIR authorization for access, its metadata must support automated discovery of OAuth2 endpoints.' do
        assert @conformance.class == FHIR::DSTU2::Conformance, 'Expected valid DSTU2 Conformance resource'
        oauth_metadata = @client.get_oauth2_metadata_from_conformance
        assert !oauth_metadata.nil?, 'No OAuth Metadata in conformance statement'
        authorize_url = oauth_metadata[:authorize_url]
        token_url = oauth_metadata[:token_url]
        assert !authorize_url.blank?, 'No authorize URI provided in conformance statement.'
        assert (authorize_url =~ /\A#{URI::regexp(['http', 'https'])}\z/) == 0, "Invalid authorize url: '#{authorize_url}'"
        assert !token_url.blank?, 'No token URI provided in conformance statement.'
        assert (token_url =~ /\A#{URI::regexp(['http', 'https'])}\z/) == 0, "Invalid token url: '#{token_url}'"

        registration_url = nil

        warning {
          security_info = @conformance.rest.first.security.extension.find{|x| x.url == 'http://fhir-registry.smarthealthit.org/StructureDefinition/oauth-uris' }
          registration_url = security_info.extension.find{|x| x.url == 'register'}
          registration_url = registration_url.value if registration_url
          assert !registration_url.blank?,  'No dynamic registration endpoint in conformance.'
          assert (registration_url =~ /\A#{URI::regexp(['http', 'https'])}\z/) == 0, "Invalid registration url: '#{registration_url}'"

          manage_url = security_info.extension.find{|x| x.url == 'manage'}
          manage_url = manage_url.value if manage_url
          assert !manage_url.blank?,  'No user-facing authorization management workflow entry point for this FHIR server.'
        }

        @instance.update(oauth_authorize_endpoint: authorize_url, oauth_token_endpoint: token_url, oauth_register_endpoint: registration_url)
      end

      test '05', '', 'Conformance Statement describes SMART on FHIR core capabilities',
           'http://www.hl7.org/fhir/smart-app-launch/conformance/',
           'A SMART on FHIR server can convey its capabilities to app developers by listing a set of the capabilities.',
           :optional do

        required_capabilities = ['launch-ehr',
                                 'launch-standalone',
                                 'client-public',
                                 'client-confidential-symmetric',
                                 'sso-openid-connect',
                                 'context-ehr-patient',
                                 'context-standalone-patient',
                                 'context-standalone-encounter',
                                 'permission-offline',
                                 'permission-patient',
                                 'permission-user'
        ]

        assert @conformance.class == FHIR::DSTU2::Conformance, 'Expected valid DSTU2 Conformance resource'
        extensions = @conformance.try(:rest).try(:first).try(:security).try(:extension)
        assert !extensions.nil?, 'No SMART capabilities listed in conformance.'
        capabilities = extensions.select{|x| x.url == 'http://fhir-registry.smarthealthit.org/StructureDefinition/capabilities' }
        assert !capabilities.nil?, 'No SMART capabilities listed in conformance.'
        available_capabilities = capabilities.map{ |v| v.valueCode}
        missing_capabilities = (required_capabilities - available_capabilities)
        assert missing_capabilities.empty?, "Conformance statement does not list required SMART capabilties: #{missing_capabilities.join(', ')}"
      end

      test '06', '', 'Conformance Statement lists supported Argonaut profiles, operations and search parameters',
           'http://www.fhir.org/guides/argonaut/r2/Conformance-server.html',
           'The Argonaut Data Query Server shall declare a Conformance identifying the list of profiles, operations, search parameter supported.' do

        assert @conformance.class == FHIR::DSTU2::Conformance, 'Expected valid DSTU2 Conformance resource'

        begin
          @instance.save_supported_resources(@conformance)
        rescue => e
          assert false, 'Conformance Statement could not be parsed.'
        end

        assert @instance.conformance_supported?(:Patient, [:read]), 'Patient resource with read interaction is not listed in conformance statement.'

      end

    end

  end
end
