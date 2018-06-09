module PubGrub
  class Incompatibility
    ConflictCause = Struct.new(:incompatibility, :satisfier)

    attr_reader :terms, :cause

    def initialize(terms, cause:)
      @cause = cause
      @terms = cleanup_terms(terms)
    end

    def failure?
      terms.empty? || terms.length == 1 && terms[0].package.name == :root
    end

    def to_s
      case cause
      when :dependency
        raise unless terms.length == 2
        "#{terms[0]} depends on #{terms[1].invert}"
      else
        # generic
        if terms.length == 1
          term = terms[0]
          if term.positive?
            "#{terms[0]} is forbidden"
          else
            "#{terms[0].invert} is required"
          end
        else
          "one of { #{terms.map(&:to_s).join(", ")} } must be false"
        end
      end
    end

    def inspect
      "#<#{self.class} #{to_s}>"
    end

    private

    def cleanup_terms(terms)
      terms.each do |term|
        raise "#{term.inspect} must be a term" unless term.is_a?(Term)
      end

      # Optimized simple cases
      return terms if terms.length <= 1
      return terms if terms.length == 2 && terms[0].package != terms[1].package

      terms.group_by(&:package).map do |package, common_terms|
        common_terms.inject do |acc, term|
          acc.intersect(term)
        end
      end
    end
  end
end
