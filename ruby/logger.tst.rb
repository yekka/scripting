require 'simplecov'
SimpleCov.start

require 'stringio'
require 'test/unit'
require_relative '../basic.rb'
require_relative '../logger.rb'

class DebugInfoCollector
  def initialize
    @buffer = ""
  end
  def debug &block
    @buffer += yield
  end
  def string
    @buffer
  end
end

class LogManager
  attr_reader :levels, :minlevel
end

class TestLogger < Test::Unit::TestCase
  def test_formatters
    a = StringIO.new
    b = StringIO.new
    c = StringIO.new
    log = LogManager.new
    log.add a, :formatter => :trivial
    log.add b, :formatter => proc { |a, b, c, d| "Hello\n" }
    log.add c
    log.warn "I dare you!"
    assert_equal "WARN: I dare you!\n", a.string
    assert_equal "Hello\n", b.string
    assert_equal "[#{format "%12s", MYNAME}] WARN: I dare you!\n", c.string
  end
  def setup_levels
    @log = LogManager.new
    @ios = []
    @allLevels = Logger::SEV_LABEL_INV.keys
    @allLevels.each do |level|
      io = StringIO.new
      @ios << io
      @log.add io, :level => level, :formatter => :trivial
    end
  end
  def test_levels
    setup_levels
    results = Array.new @allLevels.size, "Hello\n"
    @allLevels.each do |level|
      @log.send level, "Hello"
    end
    Logger::WARN.upto(Logger::FATAL) do |i|
      prefix = Logger::SEV_LABEL[i] + ": "
      results[i] = prefix + results[i]
    end
    0.upto(@allLevels.size - 1) do |i|
      assert_equal results[i..-1].join, @ios[i].string
    end
  end
  def test_emitters1
    setup_levels
    prefix = "X"
    @log.message :note do
      prefix = prefix * 3
      emit "#{prefix}: Hello from "
      emit ({
        :debug => "Debug ",
        :info  => "Info ",
        :note  => "Note ",
        :warn  => "Warn ",
        :error => "Error ",
        :fatal => "Fatal "
      })
      emit ({
        :debug => "(D)",
        :info  => "(I)",
        :note  => "(N)",
        :warn  => "(W)",
        :error => "(E)",
        :fatal => "(F)"
      })
    end
    @log.message :error do
      emit "Bye from "
      emit ({
        :debug => "Debug ",
        :info  => "Info ",
        :note  => "Note ",
        :warn  => "Warn ",
        :error => "Error ",
        :fatal => "Fatal "
      })
      emit ({
        :debug => "(D)",
        :info  => "(I)",
        :note  => "(N)",
        :warn  => "(W)",
        :error => "(E)",
        :fatal => "(F)"
      })
    end
    expected_results = [
      "XXX: Hello from Debug (D)\nERROR: Bye from Debug (D)\n",
      "XXX: Hello from Info (I)\nERROR: Bye from Info (I)\n",
      "XXX: Hello from Note (N)\nERROR: Bye from Note (N)\n",
      "ERROR: Bye from Warn (W)\n",
      "ERROR: Bye from Error (E)\n",
      ""
    ]
    0.upto(@ios.size - 1) do |i|
      assert_equal expected_results[i], @ios[i].string
    end
  end
  def test_emitters2
    log = LogManager.new
    wl = StringIO.new
    log.add wl, :formatter => :trivial, :level => :warn
    il = StringIO.new
    log.add il, :formatter => :trivial, :level => :info
    log.message :warn do
      emit "Hello"
      emit ({
        :warn => "!",
        :info => " World!"
      })
    end
    assert_equal "WARN: Hello World!\n", il.string
    assert_equal "WARN: Hello!\n", wl.string
  end
  def test_emitters3
    log = LogManager.new
    fl = StringIO.new
    log.add fl, :level => :fatal, :formatter => :trivial
    dl = StringIO.new
    log.add dl, :level => :debug, :formatter => :trivial
    nl1 = StringIO.new
    log.add nl1, :level => :note, :formatter => :trivial
    nl2 = StringIO.new
    log.add nl2, :level => :note, :formatter => :trivial
    nl3 = StringIO.new
    log.add nl3, :level => :note, :formatter => :trivial
    log.message :error do
      emit ({
        :info => "INFO",
        :warn => "ERROR"
      })
    end
    assert_equal "ERROR: INFO\n", dl.string
    assert_equal "ERROR: ERROR\n", nl1.string
    assert_equal "ERROR: ERROR\n", nl2.string
    assert_equal "ERROR: ERROR\n", nl3.string
    assert_equal "", fl.string
  end
  def test_emitters4
    log = LogManager.new
    fl = StringIO.new
    log.add fl, :level => :fatal, :formatter => :trivial
    il = StringIO.new
    log.add il, :level => :info, :formatter => :trivial
    dl = StringIO.new
    log.add dl, :level => :debug, :formatter => :trivial
    log.message :debug do
      emit ({
        :debug => "Message"
      })
    end
    assert_equal "", fl.string
    assert_equal "", il.string
    assert_equal "Message\n", dl.string
  end
  def test_emitters5
    LogManager.DBG = DebugInfoCollector.new
    log = LogManager.new
    fl = StringIO.new
    log.add fl, :level => :fatal, :formatter => :trivial
    nl1 = StringIO.new
    log.add nl1, :level => :note, :formatter => :trivial
    nl2 = StringIO.new
    log.add nl2, :level => :note, :formatter => :trivial
    nl3 = StringIO.new
    log.add nl3, :level => :note, :formatter => :trivial
    log.message :info do
      emit "Hello!"
    end
    assert_equal "", LogManager::DBG.string
    log.message :note do
      "Hello!"
    end
    refute_equal "", LogManager::DBG.string
  end
  def test_handle_01
    log = LogManager.new
    fl = StringIO.new
    fh = log.add fl, :level => :fatal, :formatter => :trivial
    dl = StringIO.new
    dh = log.add dl, :level => :debug, :formatter => :compact
    nl1 = StringIO.new
    nh1 = log.add nl1, :level => :note, :formatter => :verbose
    nl2 = StringIO.new
    nh2 = log.add nl2, :level => :note, :formatter => :extended
    nl3 = StringIO.new
    nh3 = log.add nl3, :level => :note, :formatter => :trivial
    assert_equal [1, 0, 3, 0, 0, 1], log.levels.map{|i|i or 0}
    assert_equal 0, log.minlevel
    dh.modify :level => :warn
    nh1.modify :formatter => :trivial, :level => :warn
    fh.level = :error
    assert_equal [0, 0, 2, 2, 1, 0], log.levels.map{|i|i or 0}
    assert_equal 2, log.minlevel
  end
  def test_handle_02
    log = LogManager.new
    ll = StringIO.new
    hh = log.add ll, :formatter => :trivial, :level => :info
    assert_equal 1, log.minlevel
    log.debug "gibberish"
    hh.level = :debug
    assert_equal 0, log.minlevel
    log.debug "first line"
    hh.modify :level => :warn, :formatter => :compact
    assert_equal 3, log.minlevel
    log.info "gibberish"
    log.error "second line"
    hh.formatter = proc { |_1, _2, _3, _4| "third line" }
    log.debug "gibberish"
    log.fatal "gibberish"
    ll.rewind
    lines = ll.lines
    assert_equal "first line\n", lines.next
    assert_equal "#{format "[%12s]", MYNAME} ERROR: second line\n", lines.next
    assert_equal "third line", lines.next
    begin
      lines.next
      assert false
    rescue StopIteration
    end
  end
end
