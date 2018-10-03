require 'fhir_client'
require 'pry'
#require File.expand_path '../../../app.rb', __FILE__
#require './models/testing_instance'
require 'dm-core'
require 'csv'
require 'colorize'
require 'optparse'

require_relative '../app'
require_relative '../app/endpoint'
require_relative '../app/helpers/configuration'
require_relative '../app/sequence_base'
require_relative '../app/models'

include Inferno

def suppress_output
  begin
    original_stderr = $stderr.clone
    original_stdout = $stdout.clone
    $stderr.reopen(File.new('/dev/null', 'w'))
    $stdout.reopen(File.new('/dev/null', 'w'))
    retval = yield
  rescue Exception => e
    $stdout.reopen(original_stdout)
    $stderr.reopen(original_stderr)
    raise e
  ensure
    $stdout.reopen(original_stdout)
    $stderr.reopen(original_stderr)
  end
  retval
end

def print_requests(result)
  result.request_responses.map do |req_res|
    req_res.response_code.to_s + ' ' + req_res.request_method.upcase + ' ' + req_res.request_url
  end
end

def execute(instance, sequences)

  client = FHIR::Client.new(instance.url)
  client.use_dstu2
  client.default_json

  sequence_results = []

  fails = false

  system "clear"
  puts "\n"
  puts "==========================================\n"
  puts " Testing #{sequences.length} Sequences"
  puts "==========================================\n"
  sequences.each do |sequence_info|

    sequence = sequence_info['sequence']
    sequence_info.each do |key, val|
      if key != 'sequence'
        if val.is_a?(Array) || val.is_a?(Hash)
          instance.send("#{key.to_s}=", val.to_json) if instance.respond_to? key.to_s
        elsif val.is_a?(String) && val.downcase == 'true'
          instance.send("#{key.to_s}=", true) if instance.respond_to? key.to_s
        elsif val.is_a?(String) && val.downcase == 'false'
          instance.send("#{key.to_s}=", false) if instance.respond_to? key.to_s
        else
          instance.send("#{key.to_s}=", val) if instance.respond_to? key.to_s
        end
      end
    end
    instance.save
    sequence_instance = sequence.new(instance, client, false)
    sequence_result = nil

    suppress_output{sequence_result = sequence_instance.start}
    # sequence_result = sequence_instance.start

    sequence_results << sequence_result

    checkmark = "\u2713"
    puts "\n" + sequence.sequence_name + " Sequence: \n"
    sequence_result.test_results.each do |result|
      print " "
      if result.result == 'pass'
        print "#{checkmark.encode('utf-8')} pass".green
        print " - #{result.test_id} #{result.name}\n"
      elsif result.result == 'skip'
        print "* skip".yellow
        print " - #{result.test_id} #{result.name}\n"
        puts "    Message: #{result.message}"
      elsif result.result == 'fail'
        if result.required
          print "X fail".red
          print " - #{result.test_id} #{result.name}\n"
          puts "    Message: #{result.message}"
          print_requests(result).map do |req|
            puts "    #{req}"
          end
          fails = true
        else
          print "X fail (optional)".light_black
          print " - #{result.test_id} #{result.name}\n"
          puts "    Message: #{result.message}"
          print_requests(result).map do |req|
            puts "    #{req}"
          end
        end
      elsif sequence_result.result == 'error'
        print "X error".magenta
        print " - #{result.test_id} #{result.name}\n"
        puts "    Message: #{result.message}"
        print_requests(result).map do |req|
          puts "      #{req}"
        end
        fails = true
      end
    end
    print "\n" + sequence.sequence_name + " Sequence Result: "
    if sequence_result.result == 'pass'
      puts 'pass '.green + checkmark.encode('utf-8').green
    elsif sequence_result.result == 'fail'
      puts 'fail '.red + 'X'.red
      fails = true
    elsif sequence_result.result == 'error'
      puts 'error '.magenta + 'X'.magenta
      fails = true
    elsif sequence_result.result == 'skip'
      puts 'skip '.yellow + '*'.yellow
    end
    puts "---------------------------------------------\n"
  end

  failures_count = "" + sequence_results.select{|s| s.result == 'fail'}.count.to_s
  passed_count = "" + sequence_results.select{|s| s.result == 'pass'}.count.to_s
  skip_count = "" + sequence_results.select{|s| s.result == 'skip'}.count.to_s
  print " Result: " + failures_count.red + " failed, " + passed_count.green + " passed"
  if sequence_results.select{|s| s.result == 'skip'}.count > 0
    print (", " + sequence_results.select{|s| s.result == 'skip'}.count.to_s).yellow + " skipped"
  end
  if sequence_results.select{|s| s.result == 'error'}.count > 0
    print (", " + sequence_results.select{|s| s.result == 'error'}.count.to_s).yellow + " error"
  end
  puts "\n=============================================\n"

  return_value = 0
  return_value = 1 if fails

  return_value

end

namespace :inferno do |argv|

  desc 'Generate List of All Tests'
  task :tests_to_csv, [:group, :filename] do |task, args|
    args.with_defaults(group: 'active', filename: 'testlist.csv')
    case args.group
    when 'active'
      test_group = Inferno::Sequence::SequenceBase.ordered_sequences.reject {|sb| sb.inactive?}
    when 'inactive'
      test_group = Inferno::Sequence::SequenceBase.ordered_sequences.select {|sb| sb.inactive?}
    when 'all'
      test_group = Inferno::Sequence::SequenceBase.ordered_sequences
    else
      puts "#{args.group} is not valid argument.  Valid arguments include:
                  active
                  inactive
                  all"
      exit
    end

    flat_tests = test_group.map  do |klass|
      klass.tests.map do |test|
        test[:sequence] = klass.to_s
        test[:sequence_required] = !klass.optional?
        test
      end
    end.flatten

    csv_out = CSV.generate do |csv|
      csv << ['Version', VERSION, 'Generated', Time.now]
      csv << ['', '', '', '', '']
      csv << ['Test ID', 'Reference', 'Sequence/Group', 'Test Name', 'Required?', 'Reference URI']
      flat_tests.each do |test|
        csv <<  [test[:test_id], test[:ref], test[:sequence].split("::").last, test[:name], test[:sequence_required] && test[:required], test[:url] ]
      end
    end

    File.write(args.filename, csv_out)

  end

  desc 'Generate automated run configuration'
  task :generate_config, [:server] do |task, args|

    sequences = []
    requires = []
    defines = []

    input = ''

    output = {server: args[:server], arguments: {}, sequences: []}
    Inferno::Sequence::SequenceBase.ordered_sequences.each do |seq|
      unless input == 'a'
        print "\nInclude #{seq.name} (y/n/a)? "
        input = STDIN.getc
      end

      if input == 'a' || input == 'y'
        output[:sequences].push({sequence: seq.name.demodulize})
        sequences << seq
        seq.requires.each do |req|
          requires << req unless (requires.include?(req) || defines.include?(req) || req == :url)
        end
        defines.push(*seq.defines)
      end

    end

    STDOUT.print "\n"

    requires.each do |req|
      input = ""

      if req == :initiate_login_uri
        input = 'http://localhost:4568/launch'
      elsif req == :redirect_uris
        input = 'http://localhost:4568/redirect'
      else
        STDOUT.flush
        STDOUT.print "\nEnter #{req.to_s.upcase}: ".light_black
        STDOUT.flush
        input = STDIN.gets.chomp
      end

      output[:arguments][req] = input
    end

    File.open('config.json', 'w') { |file| file.write(JSON.pretty_generate(output)) }

  end

  desc 'Execute sequence against a FHIR server'
  task :execute, [:server] do |task, args|

    FHIR.logger.level = Logger::UNKNOWN
    sequences = []
    requires = []
    defines = []

    Inferno::Sequence::SequenceBase.ordered_sequences.each do |seq|
      if args.extras.include? seq.sequence_name.split('Sequence')[0]
        seq.requires.each do |req|
          oauth_required ||= (req == :initiate_login_uri)
          requires << req unless (requires.include?(req) || defines.include?(req) || req == :url)
        end
        defines.push(*seq.defines)
        sequences << seq
      end
    end

    instance = Inferno::Models::TestingInstance.new(url: args[:server])
    instance.save!

    o = OptionParser.new

    o.banner = "Usage: rake inferno:execute [options]"
    requires.each do |req|
      o.on("--#{req.to_s} #{req.to_s.upcase}") do  |value|
        instance.send("#{req.to_s}=", value) if instance.respond_to? req.to_s
      end
    end

    arguments = o.order!(ARGV) {}

    o.parse!(arguments)

    if requires.include? :client_id
      puts 'Please register the application with the following information (enter to continue)'
      #FIXME
      puts "Launch URI: http://localhost:4567/#{base_path}/#{instance.id}/#{instance.client_endpoint_key}/launch"
      puts "Redirect URI: http://localhost:4567/#{base_path}/#{instance.id}/#{instance.client_endpoint_key}/redirect"
      STDIN.getc
      print "            \r"
    end

    input_required = false
    param_list = ""
    requires.each do |req|
      if instance.respond_to?(req) && instance.send(req).nil?
        puts "\nPlease provide the following required fields:\n" unless input_required
        print "  #{req.to_s.upcase}: ".light_black
        value_input = gets.chomp
        instance.send("#{req}=", value_input)
        input_required = true
        param_list = "#{param_list} --#{req.to_s.upcase} #{value_input}"
      end
    end
    instance.save!

    if input_required
      puts ""
      puts "\nIn the future, run with the following command:\n\n"
      puts "  rake inferno:execute[#{instance.url},#{args.extras.join(',')}] -- #{param_list}".light_black
      puts ""
      print "(enter to continue)".red
      STDIN.getc
      print "            \r"
    end

    exit execute(instance, sequences.map{|s| {'sequence' => s}})

  end

  desc 'Execute sequence against a FHIR server'
  task :execute_batch, [:config] do |task, args|
    file = File.read(args.config)
    config = JSON.parse(file)

    instance = Inferno::Models::TestingInstance.new(url: config['server'], initiate_login_uri: 'http://localhost:4568/launch', redirect_uris: 'http://localhost:4568/redirect')
    instance.save!
    client = FHIR::Client.new(config['server'])
    client.use_dstu2
    client.default_json

    config['arguments'].each do |key, val|
      if instance.respond_to?(key)
        if val.is_a?(Array) || val.is_a?(Hash)
          instance.send("#{key.to_s}=", val.to_json) if instance.respond_to? key.to_s
        elsif val.is_a?(String) && val.downcase == 'true'
          instance.send("#{key.to_s}=", true) if instance.respond_to? key.to_s
        elsif val.is_a?(String) && val.downcase == 'false'
          instance.send("#{key.to_s}=", false) if instance.respond_to? key.to_s
        else
          instance.send("#{key.to_s}=", val) if instance.respond_to? key.to_s
        end
      end
    end

    sequences = config['sequences'].map do |sequence|
      sequence_name = sequence
      out = {}
      if !sequence.is_a?(Hash)
        out = {
          'sequence' => Inferno::Sequence::SequenceBase.subclasses.find{|x| x.name.demodulize.start_with?(sequence_name)}
        }
      else
        out = sequence
        out['sequence'] = Inferno::Sequence::SequenceBase.subclasses.find{|x| x.name.demodulize.start_with?(sequence['sequence'])}
      end

      out

    end

    exit execute(instance, sequences)
  end

end

namespace :terminology do |argv|

  desc 'post-process LOINC Top 2000 common lab results CSV'
  task :process_loinc, [] do |t, args|
    require 'find'
    require 'csv'
    puts 'Looking for `./resources/terminology/Top2000*.csv`...'
    loinc_file = Find.find('resources/terminology').find{|f| /Top2000.*\.csv$/ =~f }
    if loinc_file
      output_filename = 'resources/terminology/terminology_loinc_2000.txt'
      puts "Writing to #{output_filename}..."
      output = File.open(output_filename,'w:UTF-8')
      line = 0
      begin
        CSV.foreach(loinc_file, encoding: 'iso-8859-1:utf-8', headers: true) do |row|
          line += 1
          next if row.length <=1 || row[1].nil? # skip the categories
          #              CODE    | DESC
          output.write("#{row[0]}|#{row[1]}\n")
        end
      rescue Exception => e
        puts "Error at line #{line}"
        puts e.message
      end
      output.close
      puts 'Done.'
    else
      puts 'LOINC file not found.'
      puts 'Download the LOINC Top 2000 Common Lab Results file'
      puts '  -> https://loinc.org/download/loinc-top-2000-lab-observations-us-csv/'
      puts 'copy it into your `./resources/terminology` folder, and rerun this task.'
    end
  end

  desc 'post-process SNOMED Core Subset file'
  task :process_snomed, [] do |t, args|
    require 'find'
    puts 'Looking for `./resources/terminology/SNOMEDCT_CORE_SUBSET*.txt`...'
    snomed_file = Find.find('resources/terminology').find{|f| /SNOMEDCT_CORE_SUBSET.*\.txt$/ =~f }
    if snomed_file
      output_filename = 'resources/terminology/terminology_snomed_core.txt'
      output = File.open(output_filename,'w:UTF-8')
      line = 0
      begin
        entire_file = File.read(snomed_file)
        puts "Writing to #{output_filename}..."
        entire_file.split("\n").each do |l|
          row = l.split('|')
          line += 1
          next if line==1 # skip the headers
          #              CODE    | DESC
          output.write("#{row[0]}|#{row[1]}\n")
        end
      rescue Exception => e
        puts "Error at line #{line}"
        puts e.message
      end
      output.close
      puts 'Done.'
    else
      puts 'SNOMEDCT file not found.'
      puts 'Download the SNOMEDCT Core Subset file'
      puts '  -> https://www.nlm.nih.gov/research/umls/Snomed/core_subset.html'
      puts 'copy it into your `./resources/terminology` folder, and rerun this task.'
    end
  end

  desc 'post-process common UCUM codes'
  task :process_ucum, [] do |t, args|
    require 'find'
    puts 'Looking for `./resources/terminology/concepts.tsv`...'
    ucum_file = Find.find('resources/terminology').find{|f| /concepts.tsv$/ =~f }
    if ucum_file
      output_filename = 'resources/terminology/terminology_ucum.txt'
      output = File.open(output_filename,'w:UTF-8')
      line = 0
      begin
        entire_file = File.read(ucum_file)
        puts "Writing to #{output_filename}..."
        entire_file.split("\n").each do |l|
          row = l.split("\t")
          line += 1
          next if line==1 # skip the headers
          output.write("#{row[0]}\n") # code
          output.write("#{row[5]}\n") if row[0]!=row[5] # synonym
        end
      rescue Exception => e
        puts "Error at line #{line}"
        puts e.message
      end
      output.close
      puts 'Done.'
    else
      puts 'UCUM concepts file not found.'
      puts 'Download the UCUM concepts file'
      puts '  -> http://download.hl7.de/documents/ucum/concepts.tsv'
      puts 'copy it into your `./resources/terminology` folder, and rerun this task.'
    end
  end

  desc 'post-process UMLS terminology file'
  task :process_umls, [] do |t, args|
    require 'find'
    require 'csv'
    puts 'Looking for `./resources/terminology/MRCONSO.RRF`...'
    input_file = Find.find('resources/terminology').find{|f| /MRCONSO.RRF$/ =~f }
    if input_file
      start = Time.now
      output_filename = 'resources/terminology/terminology_umls.txt'
      output = File.open(output_filename,'w:UTF-8')
      line = 0
      excluded = 0
      excluded_systems = Hash.new(0)
      begin
        puts "Writing to #{output_filename}..."
        CSV.foreach(input_file, headers: false, col_sep: '|', quote_char: "\x00") do |row|
          line += 1
          include_code = false
          codeSystem = row[11]
          code = row[13]
          description = row[14]
          case codeSystem
          when 'SNOMEDCT_US'
            codeSystem = 'SNOMED'
            include_code = (row[4]=='PF' && ['FN','OAF'].include?(row[12]))
          when 'LNC'
            codeSystem = 'LOINC'
            include_code = true
          when 'ICD10CM'
            codeSystem = 'ICD10'
            include_code = (row[12]=='PT')
          when 'ICD10PCS'
            codeSystem = 'ICD10'
            include_code = (row[12]=='PT')
          when 'ICD9CM'
            codeSystem = 'ICD9'
            include_code = (row[12]=='PT')
          when 'CPT'
            include_code = (row[12]=='PT')
          when 'HCPCS'
            include_code = (row[12]=='PT')
          when 'MTHICD9'
            codeSystem = 'ICD9'
            include_code = true
          when 'RXNORM'
            include_code = true
          when 'CVX'
            include_code = (['PT','OP'].include?(row[12]))
          when 'SRC'
            # 'SRC' rows define the data sources in the file
            include_code = false
          else
            include_code = false
            excluded_systems[codeSystem] += 1
          end
          if include_code
            output.write("#{codeSystem}|#{code}|#{description}\n")
          else
            excluded += 1
          end
        end
      rescue Exception => e
        puts "Error at line #{line}"
        puts e.message
      end
      output.close
      puts "Processed #{line} lines, excluding #{excluded} redundant entries."
      puts "Excluded code systems: #{excluded_systems}" if !excluded_systems.empty?
      finish = Time.now
      minutes = ((finish-start)/60)
      seconds = (minutes - minutes.floor) * 60
      puts "Completed in #{minutes.floor} minute(s) #{seconds.floor} second(s)."
      puts 'Done.'
    else
      download_umls_notice
    end
  end

  def download_umls_notice
    puts 'UMLS file not found.'
    puts 'Download the US National Library of Medicine (NLM) Unified Medical Language System (UMLS) Full Release files'
    puts '  -> https://www.nlm.nih.gov/research/umls/licensedcontent/umlsknowledgesources.html'
    puts 'Install the metathesaurus with the following data sources:'
    puts '  CVX|CVX;ICD10CM|ICD10CM;ICD10PCS|ICD10PCS;ICD9CM|ICD9CM;LNC|LNC;MTHICD9|ICD9CM;RXNORM|RXNORM;SNOMEDCT_US|SNOMEDCT;CPT;HCPCS'
    puts 'After installation, copy `{install path}/META/MRCONSO.RRF` into your `./resources/terminology` folder, and rerun this task.'
  end

  desc 'post-process UMLS terminology file for translations'
  task :process_umls_translations, [] do |t, args|
    require 'find'
    puts 'Looking for `./resources/terminology/MRCONSO.RRF`...'
    input_file = Find.find('resources/terminology').find{|f| f=='terminology/MRCONSO.RRF' }
    if input_file
      start = Time.now
      output_filename = 'resources/terminology/translations_umls.txt'
      output = File.open(output_filename,'w:UTF-8')
      line = 0
      excluded = 0
      excluded_systems = Hash.new(0)
      begin
        entire_file = File.read(input_file)
        puts "Writing to #{output_filename}..."
        current_umls_concept = nil
        translation = Array.new(10)
        entire_file.split("\n").each do |l|
          row = l.split('|')
          line += 1
          include_code = false
          concept = row[0]
          if concept != current_umls_concept && !current_umls_concept.nil?
            output.write("#{translation.join('|')}\n") unless translation[1..-2].reject(&:nil?).length < 2
            translation = Array.new(10)
            current_umls_concept = concept
            translation[0] = current_umls_concept
          elsif current_umls_concept.nil?
            current_umls_concept = concept
            translation[0] = current_umls_concept
          end
          codeSystem = row[11]
          code = row[13]
          translation[9] = row[14]
          case codeSystem
          when 'SNOMEDCT_US'
            translation[1] = code if (row[4]=='PF' && ['FN','OAF'].include?(row[12]))
          when 'LNC'
            translation[2] = code
          when 'ICD10CM'
            translation[3] = code if (row[12]=='PT')
          when 'ICD10PCS'
            translation[3] = code if (row[12]=='PT')
          when 'ICD9CM'
            translation[4] = code if (row[12]=='PT')
          when 'MTHICD9'
            translation[4] = code
          when 'RXNORM'
            translation[5] = code
          when 'CVX'
            translation[6] = code if (['PT','OP'].include?(row[12]))
          when 'CPT'
            translation[7] = code if (row[12]=='PT')
          when 'HCPCS'
            translation[8] = code if (row[12]=='PT')
          when 'SRC'
            # 'SRC' rows define the data sources in the file
          else
            excluded_systems[codeSystem] += 1
          end
        end
      rescue Exception => e
        puts "Error at line #{line}"
        puts e.message
      end
      output.close
      puts "Processed #{line} lines."
      puts "Excluded code systems: #{excluded_systems}" if !excluded_systems.empty?
      finish = Time.now
      minutes = ((finish-start)/60)
      seconds = (minutes - minutes.floor) * 60
      puts "Completed in #{minutes.floor} minute(s) #{seconds.floor} second(s)."
      puts 'Done.'
    else
      download_umls_notice
    end
  end
end
