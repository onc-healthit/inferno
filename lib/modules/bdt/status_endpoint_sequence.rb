# frozen_string_literal: true

require_relative 'bdt_base'

module Inferno
  module Sequence
    class BDTStatusSequence < BDTBase
      title 'Status Endpoint'

      description 'Verify the status endpoint conforms to the SMART Bulk Data IG for Export.'

      test_id_prefix 'Status'

      requires :bulk_url, :bulk_token_endpoint, :bulk_client_id, \
               :bulk_system_export_endpoint, :bulk_patient_export_endpoint, :bulk_group_export_endpoint, \
               :bulk_fastest_resource, :bulk_requires_auth, :bulk_since_param, :bulk_jwks_url_auth, :bulk_jwks_url_auth, \
               :bulk_public_key, :bulk_private_key

      details %(
        Status Endpoint
      )

      test 'Responds with 202 for active transaction IDs' do
        metadata do
          id '01'
          link 'http://hl7.org/fhir/uv/bulkdata/'
          description %(
            The status endpoint should return **202** status code until the export is completed.

See [https://github.com/HL7/bulk-data/blob/master/spec/export/index.md#response---in-progress-status](https://github.com/HL7/bulk-data/blob/master/spec/export/index.md#response---in-progress-status).
          )
          versions :r4
        end

        run_bdt('6.0')
      end
      test 'Replies properly in case of error' do
        metadata do
          id '02'
          link 'http://hl7.org/fhir/uv/bulkdata/'
          description %(
            Runs a set of assertions to verify that:
- The returned HTTP status code is 5XX
- The server returns a FHIR OperationOutcome resource in JSON format

Note that even if some of the requested resources cannot successfully be exported, the overall export operation MAY still succeed. In this case, the Response.error array of the completion response MUST be populated (see below) with one or more files in ndjson format containing FHIR OperationOutcome resources to indicate what went wrong.
See [https://github.com/HL7/bulk-data/blob/master/spec/export/index.md#response---error-status-1](https://github.com/HL7/bulk-data/blob/master/spec/export/index.md#response---error-status-1).
          )
          versions :r4
        end

        run_bdt('6.1')
      end
      test 'Generates valid status response' do
        metadata do
          id '03'
          link 'http://hl7.org/fhir/uv/bulkdata/'
          description %(
            Runs a set of assertions to verify that:
- The status endpoint should return **200** status code when the export is completed
- The status endpoint should respond with **JSON**
- The `expires` header (if set) must be valid date in the future
- The JSON response contains `transactionTime` which is a valid [FHIR instant](http://hl7.org/fhir/datatypes.html#instant)
- The JSON response contains the kick-off URL in `request` property
- The JSON response contains `requiresAccessToken` boolean property
- The JSON response contains an `output` array in which:
    - Every item has valid `type` property
    - Every item has valid `url` property
    - Every item may a `count` number property
- The JSON response contains an `error` array in which:
    - Every item has valid `type` property
    - Every item has valid `url` property
    - Every item may a `count` number property

          )
          versions :r4
        end

        run_bdt('6.2')
      end
    end
  end
end
