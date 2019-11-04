# frozen_string_literal: true

require_relative '../test_helper'

describe Inferno::Sequence::USCore301PatientSequence do
  before do
    @sequence_class = Inferno::Sequence::USCore301PatientSequence
    @base_url = 'http://www.example.com/fhir'
    @client = FHIR::Client.new(@base_url)
    @token = 'ABC'
    @instance = Inferno::Models::TestingInstance.create(token: @token)
    @patient_id = '123'
    @instance.patient_id = @patient_id
  end

  describe 'unauthorized search test' do
    before do
      @test = @sequence_class[:unauthorized_search]
      @sequence = @sequence_class.new(@instance, @client)
    end

    it 'fails when the token refresh response has a success status' do
      stub_request(:get, "#{@base_url}/Patient")
        .with(query: { _id: @patient_id })
        .to_return(status: 200)

      exception = assert_raises(Inferno::AssertionException) { @sequence.run_test(@test) }

      assert_equal "Bad response code: expected 401 or 406, but found 200", exception.message
    end

    it 'succeeds when the token refresh response has an error status' do
      stub_request(:get, "#{@base_url}/Patient")
        .with(query: { _id: @patient_id })
        .to_return(status: 401)

      @sequence.run_test(@test)
    end

    it 'is omitted when no token is set' do
      @instance.token = ''

      exception = assert_raises(Inferno::OmitException) { @sequence.run_test(@test) }

      assert_equal 'Do not test if no bearer token set', exception.message
    end
  end

  describe 'id search test' do
    before do
      @test = @sequence_class[:id_search]
      @sequence = @sequence_class.new(@instance, @client)
    end

    it 'fails when the search response has a status other than 200' do
      stub_request(:get, "#{@base_url}/Patient")
        .with(query: { _id: @patient_id }, headers: { authorization: "Bearer #{@token}"})
        .to_return(status: 401)

      exception = assert_raises(Inferno::AssertionException) { @sequence.run_test(@test) }

      assert_equal "Bad response code: expected 200, 201, but found 401. ", exception.message
    end

    it 'fails when a resource other than a bundle is returned' do
      stub_request(:get, "#{@base_url}/Patient")
        .with(query: { _id: @patient_id }, headers: { authorization: "Bearer #{@token}"})
        .to_return(status: 200, body: FHIR::Patient.new.to_json)

      exception = assert_raises(Inferno::AssertionException) { @sequence.run_test(@test) }

      assert_equal "Expected FHIR Bundle but found: Patient", exception.message
    end

    it 'skips the test if no results are found' do
      stub_request(:get, "#{@base_url}/Patient")
        .with(query: { _id: @patient_id }, headers: { authorization: "Bearer #{@token}"})
        .to_return(status: 200, body: FHIR::Bundle.new.to_json)

      exception = assert_raises(Inferno::SkipException) { @sequence.run_test(@test) }

      assert_equal 'No resources appear to be available for this patient. Please use patients with more information.', exception.message
    end

    # TODO: fix non-determinism of TestingInstance#patient_id
    #
    # it 'fails when the patient id does not match the requested id' do
    #   @instance.patient_id = @patient_id
    #   stub_request(:get, "#{@base_url}/Patient")
    #     .with(query: { _id: @patient_id }, headers: { authorization: "Bearer #{@token}"})
    #     .to_return(status: 200, body: wrap_resources_in_bundle(FHIR::Patient.new(id: 'ID')).to_json)

    #   exception = assert_raises(Inferno::AssertionException) { @sequence.run_test(@test) }

    #   assert_equal 'Server returned nil patient', exception.message
    # end

    it 'fails when the Patient resource is invalid' do
      bad_patient = FHIR::Patient.new(id: @patient_id)
      bad_patient.gender = 'BAD_GENDER'
      stub_request(:get, "#{@base_url}/Patient")
        .with(query: { _id: @patient_id }, headers: { authorization: "Bearer #{@token}"})
        .to_return(status: 200, body: wrap_resources_in_bundle(bad_patient).to_json)

      exception = assert_raises(Inferno::AssertionException) { @sequence.run_test(@test) }

      assert exception.message.start_with? 'Invalid Patient:'
    end

    it 'succeeds whan a patient with the correct ID is returned' do
      patient = FHIR::Patient.new(id: @patient_id)
      @sequence.instance_variable_set(:'@patient', patient)
      stub_request(:get, "#{@base_url}/Patient")
        .with(query: { _id: @patient_id }, headers: { authorization: "Bearer #{@token}"})
        .to_return(status: 200, body: wrap_resources_in_bundle(patient).to_json)

      @sequence.run_test(@test)
    end
  end
end