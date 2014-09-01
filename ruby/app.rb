class Application
  def hook_init
  end
  def log_setup
    assert (not defined? $log)
    $log = MTProxy.new(LogManager.new)
    @log_stderr = $log.add $stderr, :formatter => :compact, :level => :info
    @log_stderr = MTProxy.new @log_stderr
  end
  def opt_setup
    assert (not defined? $opt)
    $opt = MTProxy.new(OptionKeeper.new)
    add_specific_options
    $opt.add_common_options!
  end
  def opt_parse
    ARGV = $opt.permute ARGV
    @log_stderr.level = :warn  if $opt[:loglevel] == :quiet
    @log_stderr.level = :debug if $opt[:loglevel] == :verbose
    @log_stderr.level = :debug if $opt[:loglevel] == :debug
    @log_stderr.formatter = :extended if $opt[:loglevel] == :debug
  end
  def run
    hook_init
    log_setup
    begin
      opt_setup
      opt_parse
      main
      unless ShT.childless?
        ShT.each_task do |t|
          $log.warn "Task #{t.pretty_name} not waited for"
        end
        $log.info "Waiting for unfinished tasks" 
        ShT.waitall
      end
    rescue SystemExit # raised by exit
      exit $!.status
    rescue OptionParser::ParseError
      $log.message :fatal do
        emit $!.message
        emit ({ :debug => " (#{$!.class})" })
        emit "\n\n#{$opt}"
      end
      exit 1
    rescue Exception
      # Do not print backtrace for simple errors unless debugging the script
      hide_backtrace = ($!.class <= RuntimeError or \
                        $!.class <= SystemCallError)
      bt_level = hide_backtrace ? :debug : :fatal
      $log.message :fatal do
        emit $!.message
        emit ({ bt_level => " (#{$!.class})" })
        emit ({ bt_level => ["", *$!.backtrace].join("\n") })
      end
      exit 1
    end
    exit 0
  end
  def self.run &block
    if block_given?
      define_method :main, &block
    end
    app = self.new
    app.run
  end
end
