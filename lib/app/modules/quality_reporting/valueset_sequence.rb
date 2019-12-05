# frozen_string_literal: true

require_relative '../../utils/measure_operations'
require_relative '../../utils/bundle'

module Inferno
  module Sequence
    class ValueSetSequence < SequenceBase
      include MeasureOperations
      include BundleParserUtil
      title 'ValueSet Availability'

      test_id_prefix 'valueset'

      description 'Ensure that all required value sets for a target measure are available'

      test 'Check ValueSet Availability' do
        metadata do
          id '01'
          link 'https://hl7.org/fhir/STU3/valueset-operations.html#expand'
          desc 'Expand each Value Set in a measure to ensure they are available'
        end

        root = "#{__dir__}/../../../.."
        path = File.expand_path('resources/quality_reporting/CMS130/Bundle/cms130-bundle.json', root)
        bundle = FHIR::STU3::Bundle.new JSON.parse(File.read(path))
        measure_id = 'MitreTestScript-measure-col'
        measure = get_resource_by_id(bundle, measure_id)
        valueset_urls = get_all_dependent_valuesets(measure, bundle)

        missing_valuesets = []

        # NOTE if number of inspected valuesets << server total valuesets, this
        # approach is better, but if we test all valuesets on server, could
        # pull the ValueSet bundle once and search through that instead
        valueset_urls.each do |vs_url|
          res = @client.get "ValueSet/#{vs_url}", @client.fhir_headers(format: FHIR::Formats::ResourceFormat::RESOURCE_JSON)
          missing_valuesets << vs_url if res.response[:code] != 200
        end
        assert_equal [], missing_valuesets, 'Expected there to be no missing ValueSets'
      end
    end
  end
end