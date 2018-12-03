# frozen_string_literal: true

module PubGrub
  class VersionRange
    attr_reader :min, :max, :include_min, :include_max

    alias_method :include_min?, :include_min
    alias_method :include_max?, :include_max

    class Empty < VersionRange
      undef_method :min, :max
      undef_method :include_min, :include_min?
      undef_method :include_max, :include_max?

      def initialize
      end

      def empty?
        true
      end

      def intersects?(_)
        false
      end

      def allows_all?(other)
        other.empty?
      end

      def include?(_)
        false
      end

      def any?
        false
      end

      def constraints
        ["(no versions)"]
      end

      def ==(other)
        other.class == self.class
      end

      def invert
        VersionRange.any
      end

      def select_versions(_)
        []
      end
    end

    def self.empty
      Empty.new
    end

    def self.any
      new
    end

    def initialize(min: nil, max: nil, include_min: false, include_max: false)
      @min = min
      @max = max
      @include_min = include_min
      @include_max = include_max

      if min && max
        if min > max
          raise ArgumentError, "min version #{min} must be less than max #{max}"
        elsif min == max && (!include_min || !include_max)
          raise ArgumentError, "include_min and include_max must be true when min == max"
        end
      end
    end

    def include?(version)
      compare_version(version) == 0
    end

    # Partitions passed versions into [lower, within, higher]
    #
    # versions must be sorted
    def partition_versions(versions)
      min_version =
        if !min
          versions[0]
        elsif include_min?
          versions.bsearch { |v| v >= min }
        else
          versions.bsearch { |v| v > min }
        end
      min_index = min_version.nil? ? versions.size : versions.index(min_version)

      lower = versions.slice(0, min_index)
      versions = versions.slice(min_index, versions.size)

      max_version =
        if !max
          nil
        elsif include_max?
          versions.bsearch { |v| !(v <= max) }
        else
          versions.bsearch { |v| !(v < max) }
        end

      max_index = max_version.nil? ? versions.size : versions.index(max_version)

      [
        lower,
        versions.slice(0, max_index),
        versions.slice(max_index, versions.size)
      ]
    end

    # Returns verisons which are included by this range.
    #
    # versions must be sorted
    def select_versions(versions)
      partition_versions(versions)[1]
    end

    def compare_version(version)
      if min
        case version <=> min
        when -1
          return -1
        when 0
          return -1 if !include_min
        when 1
        end
      end

      if max
        case version <=> max
        when -1
        when 0
          return 1 if !include_max
        when 1
          return 1
        end
      end

      0
    end

    def strictly_lower?(other)
      return false if !max || !other.min

      case max <=> other.min
      when 0
        !include_max || !other.include_min
      when -1
        true
      when 1
        false
      end
    end

    def strictly_higher?(other)
      other.strictly_lower?(self)
    end

    def intersects?(other)
      return false if other.empty?
      return other.intersects?(self) if other.is_a?(VersionUnion)
      !strictly_lower?(other) && !strictly_higher?(other)
    end
    alias_method :allows_any?, :intersects?

    def intersect(other)
      return self.class.empty unless intersects?(other)
      return other.intersect(self) if other.is_a?(VersionUnion)

      min_range =
        if !min
          other
        elsif !other.min
          self
        else
          case min <=> other.min
          when 0
            include_min ? other : self
          when -1
            other
          when 1
            self
          end
        end

      max_range =
        if !max
          other
        elsif !other.max
          self
        else
          case max <=> other.max
          when 0
            include_max ? other : self
          when -1
            self
          when 1
            other
          end
        end

      self.class.new(
        min: min_range.min,
        include_min: min_range.include_min,
        max: max_range.max,
        include_max: max_range.include_max
      )
    end

    # The span covered by two ranges
    #
    # If self and other are contiguous, this builds a union of the two ranges.
    # (if they aren't you are probably calling the wrong method)
    def span(other)
      return self if other.empty?

      min_range =
        if !min
          self
        elsif !other.min
          other
        else
          case min <=> other.min
          when 0
            include_min ? self : other
          when -1
            self
          when 1
            other
          end
        end

      max_range =
        if !max
          self
        elsif !other.max
          other
        else
          case max <=> other.max
          when 0
            include_max ? self : other
          when -1
            other
          when 1
            self
          end
        end

      self.class.new(
        min: min_range.min,
        include_min: min_range.include_min,
        max: max_range.max,
        include_max: max_range.include_max
      )
    end

    def union(other)
      return other.union(self) if other.is_a?(VersionUnion)

      if contiguous_to?(other)
        span(other)
      else
        VersionUnion.union([self, other])
      end
    end

    def contiguous_to?(other)
      return false if other.empty?

      intersects?(other) ||
        (min == other.max && (include_min || other.include_max)) ||
        (max == other.min && (include_max || other.include_min))
    end

    def allows_all?(other)
      return true if other.empty?

      if other.is_a?(VersionUnion)
        return other.ranges.all? { |r| allows_all?(r) }
      end

      return false if max && !other.max
      return false if min && !other.min

      if min
        case min <=> other.min
        when -1
        when 0
          return false if !include_min && other.include_min
        when 1
          return false
        end
      end

      if max
        case max <=> other.max
        when -1
          return false
        when 0
          return false if !include_max && other.include_max
        when 1
        end
      end

      true
    end

    def constraints
      return ["any"] if any?
      return ["#{min}"] if min == max

      # FIXME: remove this
      if min && max && include_min && !include_max && min.respond_to?(:bump) && min.bump == max
        return ["~> #{min}"]
      end

      c = []
      c << "#{include_min ? ">=" : ">"} #{min}" if min
      c << "#{include_max ? "<=" : "<"} #{max}" if max
      c
    end

    def any?
      !min && !max
    end

    def empty?
      false
    end

    def to_s
      constraints.join(", ")
    end

    def inspect
      "#<#{self.class} #{to_s}>"
    end

    def invert
      return self.class.empty if any?

      low = VersionRange.new(max: min, include_max: !include_min)
      high = VersionRange.new(min: max, include_min: !include_max)

      if !min
        high
      elsif !max
        low
      else
        low.union(high)
      end
    end

    def ==(other)
      self.class == other.class &&
        min == other.min &&
        max == other.max &&
        include_min == other.include_min &&
        include_max == other.include_max
    end
  end
end
