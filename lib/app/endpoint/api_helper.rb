# frozen_string_literal: true

require 'sinatra/json'
require 'sinatra/base'
require 'sinatra/streaming'

module Inferno
  module ApiHelper
    def self.included(klass)
      klass.class_eval do
        helpers Sinatra::Streaming
      end
    end

    def available_test_sets
      available_modules = Inferno::Module.available_modules
      available_modules.map { |mod| test_set_to_hash(mod[1]) }
    end

    def test_set_by_id(id)
      mod = find_module(id)
      test_set_to_hash(mod)
    end

    # Filters presets based on base url, same as in home.rb for presets
    def filter_presets
      if defined?(settings.presets).nil? || settings.presets.nil?
        []
      else
        base_url = request.base_url
        base_path = Inferno::BASE_PATH&.chomp('/')

        # Only give preset as an option if the base url matches the inferno_uri specified
        settings.presets.select do |_, v|
          inferno_uri = v['inferno_uri']&.chomp('/')
          inferno_uri.nil? || inferno_uri == base_url || inferno_uri == base_url + base_path
        end
      end
    end

    # Check that in the request body, either (a) a preset was given or (b) fhir_server and test_set were given
    def verify_parameters_body
      request.body.rewind
      parameters = JSON.parse(request.body.read)
      if parameters['preset'].present?
        # Use parameters from preset
        preset = find_preset(parameters['preset'])
        preset_to_hash(parameters['preset'], preset).stringify_keys
      else
        # Use parameters for new instance
        halt 400, error_to_hash('Missing parameter fhir_server').to_json if parameters['fhir_server'].nil?
        halt 400, error_to_hash('Missing parameter test_set').to_json if parameters['test_set'].nil?
        parameters
      end
    end

    # Should be the same as "post '/?'" in home.rb
    def new_instance(parameters)
      fhir_server = parameters['fhir_server']&.chomp('/')
      test_set = find_module(parameters['test_set'])

      instance = Inferno::Models::TestingInstance.new(url: fhir_server,
                                                      name: 'instance',
                                                      base_url: request.base_url,
                                                      selected_module: test_set.name)

      # Set inputted parameter information
      instance.client_id = parameters['client_id'] unless parameters['client_id'].nil?
      unless parameters['client_secret'].nil?
        instance.confidential_client = true
        instance.client_secret = parameters['client_secret']
      end

      instance.client_endpoint_key = parameters['client_endpoint_key'].nil? ? 'strict' : parameters['client_endpoint_key']
      instance.initiate_login_uri = "#{request.base_url}#{base_path}/oauth2/#{instance.client_endpoint_key}/launch"
      instance.redirect_uris = "#{request.base_url}#{base_path}/oauth2/#{instance.client_endpoint_key}/redirect"
      instance.save!

      instance
    end

    # Find functions: finds a resource by id and verifies ids is valid
    def find_preset(id)
      presets = filter_presets
      preset = presets[id] unless presets.blank?
      halt 404, error_to_hash(unknown_id_message('preset', id)).to_json if preset.nil?
      preset
    end

    def find_instance(id)
      instance = Inferno::Models::TestingInstance.get(id)
      halt 404, error_to_hash(unknown_id_message('instance', id)).to_json if instance.nil?
      instance
    end

    def find_module(id)
      mod = Inferno::Module.get(id)
      halt 404, error_to_hash(unknown_id_message('test_set', id)).to_json if mod.nil?
      mod
    end

    def find_group(id, mod)
      group = mod.test_sets.first[1].groups.find { |set| set.id == id }
      halt 404, error_to_hash(unknown_id_message('group', id)).to_json if group.nil?
      group
    end

    def find_sequence(id, group)
      test_case = group.test_cases.find { |test| test.sequence.sequence_name == id }
      halt 404, error_to_hash(unknown_id_message('sequence', id)).to_json if test_case.nil?
      test_case.sequence
    end

    def find_result(id)
      result = Inferno::Models::SequenceResult.get(id)
      halt 404, error_to_hash(unknown_id_message('result', id)).to_json if result.nil?
      result
    end

    def find_request(id, result)
      requests = http_requests(result)
      range = (0..requests.length - 1).map(&:to_s)
      halt 404, error_to_hash(unknown_id_message('request', id)).to_json unless range.include? id
      requests[id.to_i]
    end

    # Given test_case_id in the form [default_test_set]_[group_id]_[sequence_id], extract the group_id
    def find_group_by_result(test_case_id)
      test_case_id&.split('_')&.dig(-2)
    end

    # View is either 'default' or 'guided'
    def find_view(mod)
      mod.test_sets.first[1].view
    end

    # Verify that the result belongs to the instance
    # This is not actually necessary for the request to be completed, just keeps it consistent
    def verify_result_to_instance(result, instance)
      verified = instance.latest_results.value?(result)
      halt 404, error_to_hash("Unknown result id '#{result.id}' for instance id '#{instance.id}'").to_json unless verified
    end

    # Returns all of the results of a given group
    def results_by_group(group_id, instance)
      results = instance.latest_results
      results.find_all { |result| find_group_by_result(result[1].test_case_id) == group_id }
    end

    # Returns a specific result by group and sequence id
    def results_by_sequence(sequence_id, group_id, instance)
      results = instance.latest_results
      results.find { |result| find_group_by_result(result[1].test_case_id) == group_id && result[1].name == sequence_id }
    end

    # Code copied from home.rb when creating an instance
    def sequence_class_to_sequence(sequence_class, instance)
      client = FHIR::Client.new(instance.url)
      case instance.fhir_version
      when 'stu3'
        client.use_stu3
      when 'dstu2'
        client.use_dstu2
      else
        client.use_r4
      end
      client.default_json

      sequence_class.new(instance, client, settings.disable_tls_tests)
    end

    # This is a simplified version of the actual execute endpoints
    # Temporary solution for not actually running the tests in a test case is to hard code test_set_id and test_case_id
    def execute_tests(sequences, instance, default_test_set, group_id)
      test_set_id = 'strict'
      sequences.map do |sequence|
        test_case_id = "#{default_test_set}_#{group_id}_#{sequence.sequence_name}"
        result = sequence_class_to_sequence(sequence, instance).start(test_set_id, test_case_id)
        result_to_hash(result)
      end
    end

    # Same as execute_tests but using a stream with NDJSON
    # Multiple variable is a boolean whether multiple sequences are being run (i.e. a group or a sequence is being run)
    # Temporary solution for not actually running the tests in a test case is to hard code test_set_id and test_case_id
    # Stream can time out and close, this is not well handled, now it will just not send any more information but leaves the client hanging
    def run_with_stream(sequences, group_id, default_test_set, multiple)
      test_set_id = 'strict'
      total_count = 0
      total_tests = sequences.reduce(0) { |total, seq| total + seq.test_count }

      stream do |out| # Open stream
        results = sequences.map do |sequence|
          count = 0
          test_case_id = "#{default_test_set}_#{group_id}_#{sequence.sequence_name}"

          sequence_result = sequence.start(test_set_id, test_case_id) do |_result|
            count += 1
            total_count += 1
            stream_hash = stream_to_hash(sequence, count, total_count, total_tests)
            out.puts JSON.generate(stream_hash) unless out.closed? # Send update
          end

          result_to_hash(sequence_result)
        end
        out.puts multiple ? results.to_json : results[0].to_json unless out.closed? # Send final results: Comment out to see stream in Postman
      end
    end
  end
end
