module Inferno
  module Sequence
    class PatientStandaloneLaunchSequence < SequenceBase

      group 'Authentication and Authorization'

      title 'Patient Standalone Launch Sequence'
      description 'Demonstrate the Patient Standalone Launch Sequence.'
      test_id_prefix 'PSLS'

      requires :client_id, :confidential_client, :client_secret, :oauth_authorize_endpoint, :oauth_token_endpoint, :scopes, :initiate_login_uri, :redirect_uris
      defines :token, :id_token, :refresh_token, :patient_id

      preconditions 'Client must be registered' do
        !@instance.client_id.nil?
      end

      test '01', '', 'OAuth authorize endpoint secured by transport layer security',
           'http://www.hl7.org/fhir/smart-app-launch/',
           'Apps must assure that sensitive information (authentication secrets, authorization codes, tokens) is transmitted ONLY to authenticated servers, over TLS-secured channels.', :optional do

        skip 'TLS tests have been disabled by configuration.' if @disable_tls_tests
        assert_tls_1_2 @instance.oauth_authorize_endpoint
        warning {
          assert_deny_previous_tls @instance.oauth_authorize_endpoint
        }
      end

      test '02', '', 'OAuth server redirects client browser to app redirect URI',
           'http://www.hl7.org/fhir/smart-app-launch/',
           'Client browser redirected from OAuth server to redirect URI of client app as described in SMART authorization sequence.'  do

        @instance.state = SecureRandom.uuid

        oauth2_params = {
            'response_type' => 'code',
            'client_id' => @instance.client_id,
            'redirect_uri' => @instance.base_url + BASE_PATH + '/' + @instance.id + '/' + @instance.client_endpoint_key + '/redirect',
            'scope' => @instance.scopes,
            'state' => @instance.state,
            'aud' => @instance.url
        }

        oauth2_auth_query = @instance.oauth_authorize_endpoint

        if @instance.oauth_authorize_endpoint.include? '?'
          oauth2_auth_query += "&"
        else
          oauth2_auth_query += "?"
        end

        oauth2_params.each do |key,value|
          oauth2_auth_query += "#{key}=#{CGI.escape(value)}&"
        end

        redirect oauth2_auth_query[0..-2], 'redirect'
      end

      test '03', '', 'Client app receives code parameter and correct state parameter from OAuth server at redirect URI',
           'http://www.hl7.org/fhir/smart-app-launch/',
           'Code and state are required querystring parameters. State must be the exact value received from the client.'  do

        assert @params['error'].nil?, "Error returned from authorization server:  code #{@params['error']}, description: #{@params['error_description']}"
        assert @params['state'] == @instance.state, "OAuth server state querystring parameter (#{@params['state']}) did not match state from app #{@instance.state}"
        assert !@params['code'].nil?, "Expected code to be submitted in request"
      end

      test '04', '', 'OAuth token exchange endpoint secured by transport layer security',
           'http://www.hl7.org/fhir/smart-app-launch/',
           'Apps must assure that sensitive information (authentication secrets, authorization codes, tokens) is transmitted ONLY to authenticated servers, over TLS-secured channels.', :optional do

        skip 'TLS tests have been disabled by configuration.' if @disable_tls_tests
        assert_tls_1_2 @instance.oauth_token_endpoint
        warning {
          assert_deny_previous_tls @instance.oauth_token_endpoint
        }
      end

      test '05', '', 'OAuth token exchange fails when supplied invalid Refresh Token or Client ID',
           'https://tools.ietf.org/html/rfc6749',
           'If the request failed verification or is invalid, the authorization server returns an error response.' do

        headers = {'Content-Type' => 'application/x-www-form-urlencoded' }

        oauth2_params = {
            'grant_type' => 'authorization_code',
            'code' => 'INVALID_CODE',
            'redirect_uri' => @instance.base_url + BASE_PATH + '/' + @instance.id + '/' + @instance.client_endpoint_key + '/redirect',
            'client_id' => @instance.client_id
        }

        token_response = LoggedRestClient.post(@instance.oauth_token_endpoint, oauth2_params.to_json, headers)
        assert_response_bad_or_unauthorized token_response

        oauth2_params = {
            'grant_type' => 'authorization_code',
            'code' => @params['code'],
            'redirect_uri' => @instance.base_url + BASE_PATH + '/' + @instance.id + '/' + @instance.client_endpoint_key + '/redirect',
            'client_id' => 'INVALID_CLIENT_ID'
        }

        token_response = LoggedRestClient.post(@instance.oauth_token_endpoint, oauth2_params.to_json, headers)
        assert_response_bad_or_unauthorized token_response

      end

      test '06', '', 'OAuth token exchange request succeeds when supplied correct information',
           'http://www.hl7.org/fhir/smart-app-launch/',
           "After obtaining an authorization code, the app trades the code for an access token via HTTP POST to the EHR authorization server's token endpoint URL, using content-type application/x-www-form-urlencoded, as described in section 4.1.3 of RFC6749." do

        oauth2_params = {
            'grant_type' => 'authorization_code',
            'code' => @params['code'],
            'redirect_uri' => @instance.base_url + BASE_PATH + '/' + @instance.id + '/' + @instance.client_endpoint_key + '/redirect',
        }
        if @instance.confidential_client
          oauth2_headers = {
              'Authorization' => "Basic #{Base64.strict_encode64(@instance.client_id + ':' + @instance.client_secret)}",
              'Content-Type' => 'application/x-www-form-urlencoded'
          }
        else
          oauth2_params['client_id'] = @instance.client_id
          oauth2_headers = { 'Content-Type' => 'application/x-www-form-urlencoded' }
        end
        @token_response = LoggedRestClient.post(@instance.oauth_token_endpoint, oauth2_params, oauth2_headers)
        assert_response_ok(@token_response)

      end

      test '07', '', 'Data returned from token exchange contains required information encoded in JSON',
           'http://www.hl7.org/fhir/smart-app-launch/',
           'The authorization servers response must include the HTTP Cache-Control response header field with a value of no-store, as well as the Pragma response header field with a value of no-cache. '\
    'The EHR authorization server shall return a JSON structure that includes an access token or a message indicating that the authorization request has been denied. '\
    'access_token, token_type, and scope are required. access_token must be Bearer.' do

        @token_response_headers = @token_response.headers
        @token_response_body = JSON.parse(@token_response.body)

        assert @token_response_body.has_key?('access_token'), "Token response did not contain access_token as required"

        token_retrieved_at = DateTime.now

        @instance.resource_references.each(&:destroy)
        @instance.resource_references << ResourceReference.new({resource_type: 'Patient', resource_id: @token_response_body['patient']}) if @token_response_body.key?('patient')

        @instance.save!

        @instance.update(token: @token_response_body['access_token'], token_retrieved_at: token_retrieved_at)

        [:cache_control, :pragma].each do |key|
          assert @token_response_headers.has_key?(key), "Token response headers did not contain #{key} as required"
        end

        assert @token_response_headers[:cache_control].downcase.include?('no-store'), 'Token response header must have cache_control containing no-store.'
        assert @token_response_headers[:pragma].downcase.include?('no-cache'), 'Token response header must have pragma containing no-cache.'

        ['token_type', 'scope'].each do |key|
          assert @token_response_body.has_key?(key), "Token response did not contain #{key} as required"
        end

        #case insentitive per https://tools.ietf.org/html/rfc6749#section-5.1
        assert @token_response_body['token_type'].downcase == 'bearer', 'Token type must be Bearer.'

        expected_scopes = @instance.scopes.split(' ')
        actual_scopes = @token_response_body['scope'].split(' ')

        warning {
          missing_scopes = (expected_scopes - actual_scopes)
          assert missing_scopes.empty?, "Token exchange response did not include expected scopes: #{missing_scopes}"

          assert @token_response_body.has_key?('patient'), 'No patient id provided in token exchange.'
        }

        scopes = @token_response_body['scope'] || @instance.scopes

        @instance.save!
        @instance.update(scopes: scopes)

        if @token_response_body.has_key?('id_token')
          @instance.save!
          @instance.update(id_token: @token_response_body['id_token'])
        end

        if @token_response_body.has_key?('refresh_token')
          @instance.save!
          @instance.update(refresh_token: @token_response_body['refresh_token'])
        end

      end

    end

  end
end
