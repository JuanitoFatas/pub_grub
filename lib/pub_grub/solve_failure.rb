require 'pub_grub/failure_writer'

module PubGrub
  class SolveFailure < StandardError
    def initialize(incompatibility)
      @incompatibility = incompatibility
    end

    def to_s
      FailureWriter.new(@incompatibility).write
    end
  end
end
