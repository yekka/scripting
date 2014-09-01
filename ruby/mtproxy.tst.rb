require 'test/unit'
require 'thread'
require_relative '../mtproxy.rb'

class MTProxy
  attr_reader :obj
end

class TestLogger < Test::Unit::TestCase
  def test_01
    a = MTProxy.new []
    a << 1
    a << 2
    a << 3
    assert_equal a.obj, [ 1, 2, 3]
  end

  def test_02
    b = MTProxy.new []
    Array.send :define_method, :fill do
      self << 1
      sleep 0.5
      self << 2
      sleep 0.5
      self << 3
    end
    b << 100
    thr = Thread.new do
      b.fill
    end
    sleep 0.1
    b << 101
    b << 102
    thr.join
    assert_equal b.obj, [ 100, 1, 2, 3, 101, 102 ]
  end

  def fill_sync ary
    ary.mon_synchronize do
      ary << 1
      sleep 0.5
      ary << 2
      sleep 0.5
      ary << 3
    end
  end

  def fill
    ary << 1
    sleep 0.5
    ary << 2
    sleep 0.5
    ary << 3
  end

  def test_03
    c = MTProxy.new []
    c << 100
    Thread.new do
      fill_sync c
    end
    sleep 0.1
    c << 101
    c << 102
    assert_equal c.obj, [ 100, 1, 2, 3, 101, 102 ]
  end

  def test_03a
    c = MTProxy.new []
    Thread.new do
      fill_sync c
    end
    sleep 0.1
    c << 101
    c << 102
    assert_equal c.obj, [ 1, 2, 3, 101, 102 ]
  end

  def test_04
    c = MTProxy.new []
    c << 100
    Thread.new do
      fill c
    end
    sleep 0.1
    c << 101
    c << 102
    refute_equal c.obj, [ 100, 1, 2, 3, 101, 102 ]
  end

  def test_05
    a = MTProxy.new [ 1, 2, 3 ]
    a.reverse!
    assert_equal a.obj, [ 3, 2, 1 ]
  end

  def test_06
    a = MTProxy.new [ 1, 2, 3 ]
    sum = 0
    a.each do |i|
      sum += i
    end
    assert_equal sum, 6
  end

  def test_07
    a = MTProxy.new [ 1, 2, 3 ]
    sum = a.reduce 0 do |memo, obj|
      memo += obj
    end
    assert_equal sum, 6
  end
end
