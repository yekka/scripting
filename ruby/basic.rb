MYDIR = File.dirname(File.absolute_path $0)
MYNAME = $0.split('/')[-1]

class InternalError < ScriptError; end

unless defined? assert
  def assert cond
    unless cond
      raise InternalError, "Assertion failed"
    end
  end
end


# def block_append _proc, &block
#   Proc.new do |*args, &b|
#     _proc.call(*args, &b)
#     block.call(*args, &b)
#   end
# end

# def block_prepend _proc, &block
#   Proc.new do |*args, &b|
#     block.call(*args, &b)
#     _proc.call(*args, &b)
#   end
# end

