require 'monitor'

class MTProxy
  # so we have methods like mon_synchronize in this Proxy class
  # and therefore can group several method invokations w/o releasing lock
  include MonitorMixin
  def initialize obj
    super()
    @obj = obj
  end
  def method_missing sym, *args, &block
    # TODO: add tracer and control in test that we got here as seldom as possible
    # puts "missing #{sym.inspect}"
    define_singleton_method sym do |*args, &block|
      mon_synchronize do
        @obj.send sym, *args, &block
      end
    end
    self.send sym, *args, &block
  end
end

