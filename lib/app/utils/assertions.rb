require_relative 'assertions.rb'
module Inferno
  module Assertions

    def assert(test, message="assertion failed, no message", data="")
      unless test
        raise AssertionException.new message, data
      end
    end

    def assert_equal(expected, actual, message="", data="")
      unless assertion_negated( expected == actual )
        message += " Expected: #{expected}, but found: #{actual}."
        raise AssertionException.new message, data
      end
    end

    def assert_response_ok(response, error_message="")
      unless assertion_negated( [200, 201].include?(response.code) )
        raise AssertionException.new "Bad response code: expected 200, 201, but found #{response.code}.#{" " + error_message}", response.body
      end
    end

    def assert_response_not_found(response)
      unless assertion_negated( [404].include?(response.code) )
        raise AssertionException.new "Bad response code: expected 404, but found #{response.code}", response.body
      end
    end

    def assert_response_unauthorized(response)
      unless assertion_negated( [401, 406].include?(response.code) )
        raise AssertionException.new "Bad response code: expected 401 or 406, but found #{response.code}", response.body
      end
    end

    def assert_response_bad_or_unauthorized(response)
      unless assertion_negated( [400, 401].include?(response.code) )
        raise AssertionException.new "Bad response code: expected 400 or 401, but found #{response.code}", response.body
      end
    end

    def assert_response_bad(response)
      unless assertion_negated( [400].include?(response.code) )
        raise AssertionException.new "Bad response code: expected 400, but found #{response.code}", response.body
      end
    end

    def assert_response_conflict(response)
      unless assertion_negated( [409, 412].include?(response.code) )
        raise AssertionException.new "Bad response code: expected 409 or 412, but found #{response.code}", response.body
      end
    end

    def assert_navigation_links(bundle)
      unless assertion_negated( bundle.first_link && bundle.last_link && bundle.next_link )
        raise AssertionException.new "Expecting first, next and last link to be present"
      end
    end

    def assert_bundle_response(response)
      unless assertion_negated( response.resource.class == FHIR::DSTU2::Bundle )
        # check what this is...
        found = response.resource
        begin
          found = resource_from_contents(response.body)
        rescue
          found = nil
        end
        raise AssertionException.new "Expected FHIR Bundle but found: #{found.class.name.demodulize}", response.body
      end
    end

    def assert_bundle_transactions_okay(response)
      response.resource.entry.each do |entry|
        unless assertion_negated( !entry.response.nil? )
          raise AssertionException.new "All Transaction/Batch Bundle.entry elements SHALL have a response."
        end
        status = entry.response.status
        unless assertion_negated( status && status.start_with?('200','201','204') )
          raise AssertionException.new "Expected all Bundle.entry.response.status to be 200, 201, or 204; but found: #{status}"
        end
      end
    end

    def assert_resource_content_type(client_reply, content_type)
      header = client_reply.response[:headers]['content-type']
      response_content_type = header
      response_content_type = header[0, header.index(';')] if !header.index(';').nil?

      unless assertion_negated( "application/fhir+#{content_type}" == response_content_type )
        raise AssertionException.new "Expected content-type application/fhir+#{content_type} but found #{response_content_type}", response_content_type
      end
    end

    # Based on MIME Types defined in
    # http://hl7.org/fhir/2015May/http.html#2.1.0.6
    def assert_valid_resource_content_type_present(client_reply)
      header = client_reply.response[:headers]['content-type']
      content_type = header
      charset = encoding = nil

      content_type = header[0, header.index(';')] if !header.index(';').nil?
      charset = header[header.index('charset=')+8..-1] if !header.index('charset=').nil?
      encoding = Encoding.find(charset) if !charset.nil?

      unless assertion_negated( encoding == Encoding::UTF_8 )
        raise AssertionException.new "Response content-type specifies encoding other than UTF-8: #{charset}", header
      end
      unless assertion_negated( (content_type == FHIR::Formats::ResourceFormat::RESOURCE_XML) || (content_type == FHIR::Formats::ResourceFormat::RESOURCE_JSON) )
        raise AssertionException.new "Invalid FHIR content-type: #{content_type}", header
      end
    end

    def assert_etag_present(client_reply)
      header = client_reply.response[:headers]['etag']
      assert assertion_negated( !header.nil? ), 'ETag HTTP header is missing.'
    end

    def assert_last_modified_present(client_reply)
      header = client_reply.response[:headers]['last-modified']
      assert assertion_negated( !header.nil? ), 'Last-modified HTTP header is missing.'
    end

    def assert_valid_content_location_present(client_reply)
      header = client_reply.response[:headers]['location']
      assert assertion_negated( !header.nil? ), 'Location HTTP header is missing.'
    end

    def assert_response_code(response, code)
      unless assertion_negated( code.to_s == response.code.to_s )
        raise AssertionException.new "Bad response code: expected #{code}, but found #{response.code}", response.body
      end
    end

    def assert_resource_type(response, resource_type)
      unless assertion_negated( !response.resource.nil? && response.resource.class == resource_type )
        raise AssertionException.new "Bad response type: expected #{resource_type}, but found #{response.resource.class}.", response.body
      end
    end

    def assertion_negated(expression)
      if @negated then !expression else expression end
    end

    def assert_tls_1_2(uri)
      tlsTester = TlsTester.new({uri:uri})

      unless uri.downcase.start_with?('https')
        raise AssertionException.new "URI is not HTTPS: #{uri}"
      end

      begin
        passed, msg = tlsTester.verifyEnsureTLSv1_2
        unless passed
          raise AssertionException.new msg
        end
      rescue SocketError => e
        raise AssertionException.new "Unable to connect to #{uri}: #{e.message}", e
      rescue => e
        raise AssertionException.new "Unable to connect to #{uri}: #{e.class.name}, #{e.message}"
      end
    end

    def assert_deny_previous_tls(uri)
      tlsTester = TlsTester.new({uri:uri})

      begin
        passed, msg = tlsTester.verfiyDenySSLv3
        unless passed
          raise AssertionException.new msg
        end
        passed, msg = tlsTester.verfiyDenyTLSv1_1
        unless passed
          raise AssertionException.new msg
        end
        passed, msg = tlsTester.verifyDenyTLSv1
        unless passed
          raise AssertionException.new msg
        end
      rescue SocketError => e
        raise AssertionException.new "Unable to connect to #{uri}: #{e.message}", e
      rescue => e
        raise AssertionException.new "Unable to connect to #{uri}: #{e.class.name}, #{e.message}"
      end
    end
  end
end