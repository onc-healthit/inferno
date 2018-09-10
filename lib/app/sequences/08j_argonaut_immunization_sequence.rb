module Inferno
  module Sequence
    class ArgonautImmunizationSequence < SequenceBase

      group 'Argonaut Profile Conformance'

      title 'Immunization'

      description 'Verify that Immunization resources on the FHIR server follow the Argonaut Data Query Implementation Guide'

      test_id_prefix 'ARIM'

      requires :token, :patient_id

      preconditions 'Client must be authorized' do
        !@instance.token.nil?
      end

      # --------------------------------------------------
      # Immunization Search
      # --------------------------------------------------

      test '01', '', 'Server rejects Immunization search without authorization',
           'http://www.fhir.org/guides/argonaut/r2/Conformance-server.html',
           'An Immunization search does not work without proper authorization.' do

        skip_if_not_supported(:Immunization, [:search, :read])

        @client.set_no_auth
        reply = get_resource_by_params(FHIR::DSTU2::Immunization, {patient: @instance.patient_id})
        @client.set_bearer_token(@instance.token)
        assert_response_unauthorized reply

      end

      test '02', '', 'Server supports Immunization search by patient',
           'http://www.fhir.org/guides/argonaut/r2/Conformance-server.html',
           'A client has connected to a server and fetched all immunizations for a patient.' do

        skip_if_not_supported(:Immunization, [:search, :read])

        reply = get_resource_by_params(FHIR::DSTU2::Immunization, {patient: @instance.patient_id})
        @immunization = reply.try(:resource).try(:entry).try(:first).try(:resource)
        validate_search_reply(FHIR::DSTU2::Immunization, reply)
        save_resource_ids_in_bundle(FHIR::DSTU2::Immunization, reply)

      end

      test '03', '', 'Immunization read resource supported',
           'http://www.fhir.org/guides/argonaut/r2/Conformance-server.html',
           'All servers SHALL make available the read interactions for the Argonaut Profiles the server chooses to support.' do

        skip_if_not_supported(:Immunization, [:search, :read])

        validate_read_reply(@immunization, FHIR::DSTU2::Immunization)

      end

      test '04', '', 'Immunization history resource supported',
           'http://www.fhir.org/guides/argonaut/r2/Conformance-server.html',
           'All servers SHOULD make available the vread and history-instance interactions for the Argonaut Profiles the server chooses to support.',
           :optional do

        skip_if_not_supported(:Immunization, [:history])

        validate_history_reply(@immunization, FHIR::DSTU2::Immunization)

      end

      test '05', '', 'Immunization vread resource supported',
           'http://www.fhir.org/guides/argonaut/r2/Conformance-server.html',
           'All servers SHOULD make available the vread and history-instance interactions for the Argonaut Profiles the server chooses to support.',
           :optional do

        skip_if_not_supported(:Immunization, [:vread])

        validate_vread_reply(@immunization, FHIR::DSTU2::Immunization)

      end

      test '06', '', 'Immunization resources associated with Patient conform to Argonaut profiles',
           'http://www.fhir.org/guides/argonaut/r2/StructureDefinition-argo-immunization.html',
           'Immunization resources associated with Patient conform to Argonaut profiles.' do
        test_resources_against_profile('Immunization')
      end

    end

  end
end
