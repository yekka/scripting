require 'set'
require 'monitor'

class ShellTaskFailed < RuntimeError; end

module ShellTask

  # There may be yet-non-spawned or already-waited-for tasks in this storage
  # Though, it's guaranteed that every running subtask is registered in the storage
  class TaskManager
    def initialize
      @storage = Set.new
      extend MonitorMixin
    end
    INTERFACE = Set.new
    def self.method_added sym
      INTERFACE << sym
      super sym
    end
    def childless?
      @storage.empty?
    end
    def insert task
      assert (not @storage.include? task)
      @storage << task
    end
    def delete task
      assert (@storage.include? task)
      @storage.delete task
    end
    def each_task &block
      @storage.each &block
    end
    def waitall
      @storage.each { |t| t.wait }
    end
    def killall signum = "SIGTERM"
      @storage.each do |t|
        next if t.rc # do not kill tasks that already has been waited for
        $log.info "Kill #{signum} #{t.pretty_name}"
        Process.kill signum, t.pid unless $opt[:dryrun]
      end
    end
    INTERFACE.each do |sym|
      m = instance_methods sym
      define_method sym do |*args, &block|
        mon_synchronize do
          m.call(*args, &block)
        end
      end
    end
  end


  # class CtorHelper
  #   def initialize *modifiers, &block
  #     @modifiers = modifiers << block
  #   end
  # end
  
  # The code below desperately asks for great refactoring, but it still works good enough,
  # so it will wait for a while
  class ShellTask
    @@task_manager = TaskManager.new
    # forward any call from INTERFACE to @@task_manager
    TaskManager::INTERFACE.each do |sym|
      define_method sym do |*args, &block|
        @@task_manager.send sym, *args, &block
      end
    end
    
    # helper to simplify task creation
    class ShellTaskHelper
      protected
      attr_reader :modifiers
      public
      def initialize previous, mod
        if previous
          @modifiers = previous.modifiers
        else
          @modifiers = []
        end
        @modifiers << mod
      end
      def new *args
        task = ShellTask.new *args
        @modifiers.each { |m| m.call(task) }
        task
      end
      def run *args
        task = self.new *args
        task.run
        task
      end
      def async *args
        task = self.new *args
        task.async
        task
      end
      def chdir *args
        task = self.new *args
        task.chdir *args
        task
      end
      def fail policy
        @modifiers << proc { |task|
          task.fail = policy
        }
        self
      end
      # some commands should be really run even in case of dry run
      def moist m = true
        @modifiers << proc { |task|
          task.moist = m
        }
        self
      end
      # some non-significant commands shouldn't be visible in log unless high verbosity is desired
      def quiet
        @modifiers << proc { |task|
          task.quiet = :quiet
        }
        self
      end
      def silent
        @modifiers << proc { |task|
          task.quiet = :silent
        }
        self
      end
      def name n
        @modifiers << proc { |task|
          task.name = n
        }
        self
      end
    end

    def self.run *args
      task = self.new *args
      task.run
      task
    end

    def self.async *args
      task = self.new *args
      task.async
      task
    end

    def self.fail policy
      ShellTaskHelper.new nil, proc { |task|
        task.fail = policy
      }
    end

    def self.moist m = true
      ShellTaskHelper.new nil, proc { |task|
        task.moist = m
      }
    end

    def self.quiet
      ShellTaskHelper.new nil, proc { |task|
        task.quiet = :quiet
      }
    end

    def self.silent
      ShellTaskHelper.new nil, proc { |task|
        task.quiet = :silent
      }
    end

    def self.name n
      ShellTaskHelper.new nil, proc { |task|
        task.name = n
      }
    end

    # expose member fields
    attr_reader :pid, :rc, :args
    attr_accessor :fail, :moist, :quiet, :name

    def initialize *args
      @args = args
      @fail, @moist, @quiet = false, false, false
      @pid, @rc = nil, nil
      nameidx = 0
      nameidx = 1 if args.first.class <= Hash
      @name = args[nameidx].to_s.split[0]
    end

    def async
      self.class.insert self

      unless $opt[:dryrun] and not @moist
        @pid = Process.spawn *@args
      else
        @pid = :dryrun
      end

      llev = :info
      llev = :debug if @quiet == :quiet
      # TODO: move silent to tracer
      llev = :debug if @quiet == :silent
      $log.send llev do
        argmsg = @args.map{|a|a.inspect}.join(", ")
        "Spawn #{pretty_name}: #{argmsg}"
      end

      return self
    end

    def run
      assert @pid.nil?
      self.async
      self.wait
    end

    def wait
      assert @pid
      assert (not @rc)
      unless @pid == :dryrun
        Process.wait @pid
        @rc = $?.exitstatus
      else
        @rc = 0
      end
      self.class.delete self

      msg = "Task #{pretty_name} exited with code #{@rc}"
      unless @rc == 0 or @fail == :ignore
        if [ :debug, :verbose, :info, :warn, :error, :fatal ].include? @fail
          $log.send(@fail, msg)
        else
          raise ShellTaskFailed, msg
        end
      else
        $log.debug msg
      end
      return @rc
    end

    def pretty_name
      unless @pid == :dryrun
        "#{@name}[#{@pid}]"
      else
        "#{@name}[0]"
      end
    end

    def self.chdir d, &block
      task = ShellTask.new
      task.chdir d, &block
    end

    def chdir d, &block
      dry = ($opt[:dryrun] and not @moist)
      if block_given?
        $log.info %Q{Chdir to "#{d}"}
        unless dry
          Dir.chdir d, &block
        else
          yield
        end
        $log.info %Q{Chdir to "#{Dir.pwd}"}
      else
        $log.info %Q{Chdir to "#{d}"}
        Dir.chdir d unless dry
      end
    end

    def self.pipe &block
      if block_given?
        IO.pipe do |r, w|
          $log.debug "New pipe: #{w.inspect} => #{r.inspect}"
          block.yield r, w
        end
      else
        r, w = IO.pipe
        $log.debug "New pipe: #{w.inspect} => #{r.inspect}"
        return [ r, w ]
      end
    end
  end
end

# killall subtasks before exiting
END {
  ShellTask::ShellTask.killall "SIGTERM"
}

# small helper
class Dir
  def self.empty? dir
    Dir.entries(dir).delete_if { |d| [ ".", ".." ].include? d }.empty?
  end
end

# shortcut
ShT = ShellTask::ShellTask
