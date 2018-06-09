require 'pub_grub/assignment'

module PubGrub
  class PartialSolution
    attr_reader :assignments, :decisions

    def initialize
      @assignments = []

      # { Package => Package::Version }
      @decisions = {}

      # { Package => Term }
      @terms = {}

      # { Package => Boolean }
      @required = {}
    end

    def decision_level
      @decisions.length
    end

    def relation(term)
      package = term.package
      return :overlap if !@terms.key?(package)

      @terms[package].relation(term)
    end

    def satisfies?(term)
      relation(term) == :subset
    end

    def derive(term, cause)
      add_assignment(Assignment.new(term, cause, decision_level))
    end

    def satisfier(term)
      assigned_term = nil

      assignments.each_with_index do |assignment, index|
        next unless assignment.term.package == term.package

        if assigned_term
          assigned_term = assigned_term.intersect(assignment.term)
        else
          assigned_term = assignment.term
        end

        if assigned_term.satisfies?(term)
          return assignment, index
        end
      end

      raise "#{term} unsatisfied"
    end

    # A list of unsatisfied terms
    def unsatisfied
      @terms.values.reject do |term|
        @decisions.key?(term.package)
      end
    end

    def decide(version)
      decisions[version.package] = version
      assignment = Assignment.decision(version, decision_level)
      add_assignment(assignment)
    end

    def backtrack(previous_level)
      new_assignments = assignments.select do |assignment|
        assignment.decision_level <= previous_level
      end

      @decisions = Hash[decisions.first(previous_level)]
      @assignments = []
      @terms = {}
      @required = {}

      new_assignments.each do |assignment|
        add_assignment(assignment)
      end
    end

    private

    def add_assignment(assignment)
      @assignments << assignment

      term = assignment.term
      package = term.package

      @required[package] ||= term.positive?

      if @terms.key?(package)
        old_term = @terms[package]
        @terms[package] = old_term.intersect(term)
      else
        @terms[term.package] = term
      end
    end
  end
end
