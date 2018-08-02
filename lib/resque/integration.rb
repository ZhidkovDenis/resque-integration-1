require 'resque/integration/version'

require 'active_support/all'
require 'rails/railtie'
require 'active_record'
require 'action_pack'

require 'rake'
require 'multi_json'

require 'resque'
silence_warnings { require 'resque/plugins/meta' }

require 'resque/integration/monkey_patch/verbose_formatter'
require 'resque/integration/hooks'

require 'resque/scheduler'
require 'resque/scheduler/tasks'
require 'resque-retry'

module Resque
  include Integration::Hooks
  extend Integration::Hooks

  # Resque.config is available now
  mattr_accessor :config

  def queues_info
    return @queues_info if defined?(@queues_info)

    queues_info_config = Rails.root.join('config', 'resque_queues.yml')

    @queues_info = Resque::Integration::QueuesInfo.new(config: queues_info_config)
  end

  # Seamless resque integration with all necessary plugins
  # You should define an +execute+ method (not +perform+)
  #
  # Usage:
  #   class MyJob
  #     include Resque::Integration
  #
  #     queue :my_queue
  #     unique ->(*args) { args.first }

  #     def self.execute(*args)
  #     end
  #   end
  module Integration
    autoload :Backtrace, 'resque/integration/backtrace'
    autoload :CLI, 'resque/integration/cli'
    autoload :Configuration, 'resque/integration/configuration'
    autoload :Continuous, 'resque/integration/continuous'
    autoload :Unique, 'resque/integration/unique'
    autoload :Ordered, 'resque/integration/ordered'
    autoload :LogsRotator, 'resque/integration/logs_rotator'
    autoload :QueuesInfo, 'resque/integration/queues_info'
    autoload :Extensions, 'resque/integration/extensions'
    autoload :FailureBackends, 'resque/integration/failure_backends'
    autoload :Priority, 'resque/integration/priority'

    extend ActiveSupport::Concern

    included do
      extend Backtrace

      @queue ||= :default
    end

    module ClassMethods
      # Get or set queue name (just a synonym to resque native methodology)
      def queue(name = nil)
        if name
          @queue = name
        else
          @queue
        end
      end

      # Mark Job as unique and set given +callback+ or +block+ as Unique Arguments procedure
      def unique(callback = nil, &block)
        extend Unique unless unique?

        lock_on(&(callback || block))
      end

      # Extend job with 'continuous' functionality so you can re-enqueue job with +continue+ method.
      def continuous
        extend Continuous
      end

      def unique?
        false
      end

      # Public: job used priority queues
      def priority?
        false
      end

      # Extend resque-retry.
      #
      # options - Hash of retry options (default: {}):
      #           :limit                  - Integer max number of retry attempts (default: 2)
      #           :delay                  - Integer seconds between retry attempts (default: 60)
      #           :exceptions             - Array or Hash of specific exceptions to retry (optional)
      #           :temporary              - boolean retry on temporary exceptions list (default: false)
      #           :expire_retry_key_after - Integer expire of retry key in redis (default: 3200)
      #
      # Returns nothing.
      def retrys(options = {})
        raise '`retries` should be declared higher in code than `unique`' if unique?

        extend Resque::Plugins::Retry

        @retry_limit = options.fetch(:limit, 2)
        @retry_delay = options.fetch(:delay, 60)

        @retry_exceptions = options[:exceptions] if options.key? :exceptions

        if options[:temporary]
          @retry_exceptions = @retry_exceptions && @retry_exceptions.dup || {}
          @retry_exceptions = @retry_exceptions.product([@retry_delay]).to_h if @retry_exceptions.is_a? Array

          @retry_exceptions.reverse_merge!(Rails.application.config.temporary_exceptions)
        end

        @expire_retry_key_after = options.fetch(:expire_retry_key_after, 1.hour.seconds)
      end
      alias retries retrys

      # Mark Job as ordered
      def ordered(options = {})
        extend Ordered

        self.max_iterations = options.fetch(:max_iterations, 20)
        self.uniqueness = Ordered::Uniqueness.new(&options[:unique]) if options.key?(:unique)
      end

      def prioritized
        extend Priority
      end
    end
  end # module Integration
end # module Resque

require 'resque/integration/engine'
