
module Inferno
  module Sequence
    class UsCoreR4MedicationrequestSequence < SequenceBase

      group 'US Core R4 Profile Conformance'

      title 'US Core R4 MedicationRequest Tests'

      description 'Verify that MedicationRequest resources on the FHIR server follow the Argonaut Data Query Implementation Guide'

      test_id_prefix 'MedicationRequest' # change me

      requires :token, :patient_id
      conformance_supports :MedicationRequest

      
        def validate_resource_item (resource, property, value)
          case property
          
          when 'patient'
            assert (resource.patient && resource.patient.reference.include?(value)), "patient on resource does not match patient requested"
        
          end
        end
    

      details %(
      )

      @resources_found = false
      
      test 'Server rejects MedicationRequest search without authorization' do
        metadata {
          id '1'
          link 'http://www.fhir.org/guides/argonaut/r2/Conformance-server.html'
          desc %(
          )
          versions :r4
        }
        
        @client.set_no_auth
        skip 'Could not verify this functionality when bearer token is not set' if @instance.token.blank?

        reply = get_resource_by_params(versioned_resource_class('MedicationRequest'), {patient: @instance.patient_id})
        @client.set_bearer_token(@instance.token)
        assert_response_unauthorized reply
  
      end
      
      test 'Server returns expected results from MedicationRequest search by patient' do
        metadata {
          id '2'
          link 'https://build.fhir.org/ig/HL7/US-Core-R4/CapabilityStatement-us-core-server.html'
          desc %(
          )
          versions :r4
        }
        
        search_params = {patient: @instance.patient_id}
        reply = get_resource_by_params(versioned_resource_class('MedicationRequest'), search_params)
        assert_response_ok(reply)
        assert_bundle_response(reply)

        skip 'No resources appear to be available for this patient. Please use patients with more information.' unless @resources_found

        validate_search_reply(versioned_resource_class('MedicationRequest'), reply, search_params)
  
        resource_count = reply.try(:resource).try(:entry).try(:length) || 0
        if resource_count > 0
          @resources_found = true
        end
        @medicationrequest = reply.try(:resource).try(:entry).try(:first).try(:resource)
        save_resource_ids_in_bundle(versioned_resource_class('MedicationRequest'), reply)
    
      end
      
      test 'Server returns expected results from MedicationRequest search by patient + status' do
        metadata {
          id '3'
          link 'https://build.fhir.org/ig/HL7/US-Core-R4/CapabilityStatement-us-core-server.html'
          desc %(
          )
          versions :r4
        }
        
        
        patient_val = @instance.patient_id
        status_val = @medicationrequest.try(:status)
        search_params = {'patient': patient_val, 'status': status_val}
  
        reply = get_resource_by_params(versioned_resource_class('MedicationRequest'), search_params)
        validate_search_reply(versioned_resource_class('MedicationRequest'), reply, search_params)
  
      end
      
      test 'Server returns expected results from MedicationRequest search by patient + authoredon' do
        metadata {
          id '4'
          link 'https://build.fhir.org/ig/HL7/US-Core-R4/CapabilityStatement-us-core-server.html'
          desc %(
          )
          versions :r4
        }
        
        
        patient_val = @instance.patient_id
        authoredon_val = @medicationrequest.try(:authoredOn)
        search_params = {'patient': patient_val, 'authoredon': authoredon_val}
  
        reply = get_resource_by_params(versioned_resource_class('MedicationRequest'), search_params)
        validate_search_reply(versioned_resource_class('MedicationRequest'), reply, search_params)
  
      end
      
      test 'MedicationRequest read resource supported' do
        metadata {
          id '5'
          link 'https://build.fhir.org/ig/HL7/US-Core-R4/CapabilityStatement-us-core-server.html'
          desc %(
          )
          versions :r4
        }
        
        skip_if_not_supported(:MedicationRequest, [:read])
        skip 'No resources appear to be available for this patient. Please use patients with more information.' unless @resources_found

        validate_read_reply(@medicationrequest, versioned_resource_class('MedicationRequest'))
  
      end
      
      test 'MedicationRequest vread resource supported' do
        metadata {
          id '6'
          link 'https://build.fhir.org/ig/HL7/US-Core-R4/CapabilityStatement-us-core-server.html'
          desc %(
          )
          versions :r4
        }
        
        skip_if_not_supported(:MedicationRequest, [:vread])
        skip 'No resources appear to be available for this patient. Please use patients with more information.' unless @resources_found

        validate_vread_reply(@medicationrequest, versioned_resource_class('MedicationRequest'))
  
      end
      
      test 'MedicationRequest history resource supported' do
        metadata {
          id '7'
          link 'https://build.fhir.org/ig/HL7/US-Core-R4/CapabilityStatement-us-core-server.html'
          desc %(
          )
          versions :r4
        }
        
        skip_if_not_supported(:MedicationRequest, [:history])
        skip 'No resources appear to be available for this patient. Please use patients with more information.' unless @resources_found

        validate_history_reply(@medicationrequest, versioned_resource_class('MedicationRequest'))
  
      end
      
      test 'MedicationRequest resources associated with Patient conform to Argonaut profiles' do
        metadata {
          id '8'
          link ''
          desc %(
          )
          versions :r4
        }
        
        skip 'No resources appear to be available for this patient. Please use patients with more information.' unless @resources_found
        test_resources_against_profile('MedicationRequest')
  
      end
      
      test 'All references can be resolved' do
        metadata {
          id '9'
          link 'https://www.hl7.org/fhir/DSTU2/references.html'
          desc %(
          )
          versions :r4
        }
        
        skip_if_not_supported(:MedicationRequest, [:search, :read])
        skip 'No resources appear to be available for this patient. Please use patients with more information.' unless @resources_found

        validate_reference_resolutions(@medicationrequest)
  
      end
      
    end
  end
end