require 'logger'

# TODO: rename LogManager::DBG (it is a tracer in fact)
# TODO: make a convinient interface to read and modify the tracer
# TODO: remove monkey patching, use tracer instead of debug, debug instead of info, and info instead of note

# monkey patch Logger class so as to add NOTE level between INFO and WARN
class Logger
  module Severity
    [ :DEBUG, :INFO, :WARN, :ERROR, :FATAL, :UNKNOWN ].each do |lev|
      self.send :remove_const, lev
    end
    DEBUG = 0
    INFO = 1
    NOTE = 2
    WARN = 3
    ERROR = 4
    FATAL = 5
    UNKNOWN = 6
    UNREACHABLE = (FATAL + 100)
  end
  self.send :remove_const, :SEV_LABEL
  SEV_LABEL = %w(DEBUG INFO NOTE WARN ERROR FATAL ANY)
  SEV_LABEL_INV = {
    :debug => DEBUG,
    :info  => INFO,
    :note  => NOTE,
    :warn  => WARN,
    :error => ERROR,
    :fatal => FATAL
  }
  def note?
    @level <= NOTE
  end
  def note(progname = nil, &block)
    add(NOTE, nil, progname, &block)
  end
end

class LogManager

  class DumbLogger
    def debug &block
    end
  end
  DBG = DumbLogger.new
  def self.DBG= dbg
    self.send :remove_const, :DBG
    self.send :const_set, :DBG, dbg
  end

  class Handle
    def initialize logman, logger
      @logman, @logger = logman, logger
    end
    def level
      @logger.level
    end
    def level= new
      old = @logger.level
      new = Logger::SEV_LABEL_INV[new]
      assert new
      @logman.h_mod_level old => new
      @logger.level = new
    end
    def formatter
      @logger.formatter
    end
    def formatter= new
      new = FMTR_MAP[new] || new
      @logger.formatter = new
    end
    def modify what
      what.each do |key, value|
        case key
        when :level
          self.level = value
        when :formatter
          value = FMTR_MAP[value] || value
          self.formatter = value
        else
          assert false
        end
      end
    end
    def disable!
      @logman.disable @logman
      @logman = nil
      @logger = nil
    end
  end

  FMTR_TRIVIAL = proc { |s, d, p, m|
    s = [ "DEBUG", "INFO", "NOTE" ].include?(s) ? "" : "#{s}: "
    "#{s}#{m}\n"
  }
  FMTR_COMPACT = proc { |s, d, p, m|
    s = [ "DEBUG", "INFO", "NOTE" ].include?(s) ? "" : "#{s}: "
    h = format "[%12s]", ::MYNAME, Process.pid
    "#{h} #{s}#{m}\n"
  }
  FMTR_VERBOSE = proc { |s, d, p, m|
    s = [ "DEBUG", "INFO", "NOTE" ].include?(s) ? "" : "#{s}: "
    h = format "[%12s %5d]", ::MYNAME, Process.pid
    "#{h} #{s}#{m}\n"
  }
  FMTR_EXTENDED = proc { |s, d, p, m|
    s = [ "DEBUG", "INFO", "NOTE" ].include?(s) ? "" : "#{s}: "
    t = Time.now.strftime "%H:%M:%S.%L"
    h = format "[%s %12s %5d]", t, ::MYNAME, Process.pid
    "#{h} #{s}#{m}\n"
  }

  FMTR_MAP = {
    :trivial  => FMTR_TRIVIAL,
    :compact  => FMTR_COMPACT,
    :verbose  => FMTR_VERBOSE,
    :extended => FMTR_EXTENDED
  }

  def initialize
    @backends = []
    @levels = []
    def @levels.[] key
      val = super(key)
      val || 0
    end
    @minlevel = Logger::UNREACHABLE
  end
  # EXAMPLE:
  # $log.add $stderr, :formatter => :trivial, :level => :warn
  def add io, opts = {}
    logger = Logger.new io
    logger.formatter = FMTR_MAP[opts[:formatter]] || opts[:formatter] || FMTR_COMPACT
    opts.delete :formatter
    assert Logger::SEV_LABEL_INV[opts[:level]] if opts[:level]
    logger.level = Logger::SEV_LABEL_INV[opts[:level]] || Logger::NOTE
    opts.delete :level
    assert false unless opts.empty?
    @levels[logger.level] += 1
    @minlevel = [@minlevel, logger.level].min
    @backends << logger
    Handle.new self, logger
  end
  def disable logger
    h_mod_level logger.level => Logger::UNREACHABLE
    res = @backends.delete logger
    assert res
  end
  # EXAMPLE:
  # $log.message :info do
  #   emit "Hello "
  #   emit ({
  #     :debug   => "World! (#{Process.pid})",
  #     :note    => "World!",
  #     :warn    => "Wld!"
  #   })
  # end
  # We don't want to build strings which will never be used,
  # so don't build strings which have no chance to be used
  def message symlev, &block
    level = Logger::SEV_LABEL_INV[symlev]
    return if @minlevel > level
    DBG.debug { "do not skip\n" }
    @parts = []
    instance_eval &block
    @backends.each do |lgr|
      ll = lgr.level
      msg = ""
      @parts.each do |p|
        if p.class == Array
          m = p[ll]
          msg << m if m
        else
          msg << p
        end
      end
      lgr.send symlev, msg unless msg.empty?
    end
  end

  private
  def emit msg
    if msg.class <= Hash
      m = []
      msg.each do |k, v|
        m[Logger::SEV_LABEL_INV[k]] = v
      end
      assert (not m.empty?)
      prev = m.last
      (m.size - 2).downto(0) do |i|
        cur = m[i]
        prev = cur if cur
        m[i] = prev unless cur
      end
      msg = m
    end
    @parts << msg
  end

  public
  # callback for handler
  def h_mod_level hash
    assert (hash.size == 1)
    hash.each do |old, new|
      # conservatively lower loglevel before correct level determined
      @minlevel = [@minlevel, new].min
      @levels[old] -= 1
      assert (@levels[old] >= 0)
      @levels[new] += 1
      @levels.each_with_index do |lognum, index|
        if lognum and lognum > 0
          @minlevel = index
          break
        end
      end
    end
  end

  Logger::SEV_LABEL_INV.each do |key, value|
    define_method(key) do |*msg, &block|
      @backends.each do |lgr|
        lgr.send key, *msg, &block
      end
    end
  end
end

#$log = LogManager.new
#$log.add $stderr, :formatter => :simple, :level => Logger::NOTE
