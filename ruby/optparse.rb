require 'optparse'

# TODO: move common_options to app.rb

# TODO: cmd --stdout=file --stderr=-(default) --stderr=+file --logfile=info(default):-(default) --logfile=+debug:file
# ==========  --stdout=file --stderr=+file --logfile=+debug:file
# TODO: cmd --log=debug:file

class UsageError < OptionParser::ParseError; end

class OptionKeeper < OptionParser
  def initialize
    super
    @options = Hash.new
  end
  def [] key
    @options[key]
  end
  def []= key, value
    @options[key] = value
  end
  def add_common_options!
    separator ""
    separator "Redirection options:"
    on('--stdlog=FILE', "redirect stderr (param format [+][LEVEL:]FILE)") do |fname|
      match = fname.match /^(\+?)([^:]*:)?(.*)$/
      raise UsageError, "Incorrect redirection format: '#{fname}'" unless match
      level = :info
      levelname = match[2][0...-1]
      unless levelname.empty?
        level = SEV_LABEL_INV[levelname.to_sym]
        raise UsageError, "Incorrect loglevel format: '#{levelname}'" unless level
      end
      fname = match[3]
      raise UsageError, "Empty filename passed to redirection option" if fname.empty?
      if match[1].empty?
        $log.info %Q{Reset logging}
        $log = MTProxy.new(LogManager.new)
      end
      $log.add File.open(fname), :level => level
    end
    separator ""
    separator "Auxilliary options:"
    on('-q', '--quiet', 'Be less verbose') do
      self[:loglevel] = :quiet
    end
    on('-v', '--verbose', 'Be more verbose') do
      self[:loglevel] = :verbose
    end
    on('--debug', 'Be extremely verbose') do
      self[:loglevel] = :debug
    end
    on('--dry-run', 'Dry run') do
      self[:dryrun] = true
    end
    on('-h', '--help', 'Show help') do
      puts self
      exit 0
    end
  end
end
