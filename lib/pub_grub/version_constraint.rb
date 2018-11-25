require 'pub_grub/version_range'

require 'rubygems/requirement'

module PubGrub
  class VersionConstraint
    attr_reader :package, :constraint, :range

    # @param package [PubGrub::Package]
    # @param constraint [String]
    def initialize(package, constraint = nil, range: nil, bitmap: nil)
      @package = package
      @constraint = Array(constraint)
      @range = range
      @bitmap = bitmap # Calculated lazily
    end

    class << self
      def parse(package, constraint)
        # TODO: Should not be hardcoded to rubygems semantics
        requirement = Gem::Requirement.new(constraint)
        ranges = requirement.requirements.map do |(op, ver)|
          case op
          when "~>"
            # TODO: not sure this is correct for prereleases
            VersionRange.new(min: ver, max: ver.bump, include_min: true)
          when ">"
            VersionRange.new(min: ver)
          when ">="
            if ver == Gem::Version.new("0")
              VersionRange.any
            else
              VersionRange.new(min: ver, include_min: true)
            end
          when "<"
            VersionRange.new(max: ver)
          when "<="
            VersionRange.new(max: ver, include_max: true)
          when "="
            VersionRange.new(min: ver, max: ver, include_min: true, include_max: true)
          when "!="
            VersionRange.new(min: ver, max: ver, include_min: true, include_max: true).invert
          else
            raise "bad version specifier: #{op}"
          end
        end

        new(package, constraint, range: ranges.inject(&:intersect))
      end

      def exact(version)
        package = version.package
        ver = Gem::Version.new(version.name)
        range = VersionRange.new(min: ver, max: ver, include_min: true, include_max: true)
        new(package, version.name, range: range)
      end

      def any(package)
        range = VersionRange.new
        new(package, nil, range: range)
      end

      def bitmap_matching(package)
        package.versions.select do |version|
          yield version
        end.inject(0) do |acc, version|
          acc | (1 << version.id)
        end
      end
    end

    def bitmap
      return @bitmap if @bitmap

      @bitmap = self.class.bitmap_matching(package) do |version|
        range.include?(Gem::Version.new(version.name))
      end
    end

    def intersect(other)
      unless package == other.package
        raise ArgumentError, "Can only intersect between VersionConstraint of the same package"
      end

      self.class.new(package, constraint + other.constraint, range: range.intersect(other.range))
    end

    def union(other)
      unless package == other.package
        raise ArgumentError, "Can only intersect between VersionConstraint of the same package"
      end

      self.class.new(package, "#{constraint_string} OR #{other.constraint_string}", range: range.union(other.range))
    end

    def invert
      new_range = range.invert
      new_constraint =
        if constraint.length == 0
          ["not >= 0"]
        elsif constraint.length == 1
          ["not #{constraint[0]}"]
        else
          ["not (#{constraint_string})"]
        end
      self.class.new(package, new_constraint, range: new_range)
    end

    def difference(other)
      intersect(other.invert)
    end

    def versions
      package.versions.select do |version|
        range.include?(Gem::Version.new(version.name))
      end
    end

    def allows_all?(other)
      bitmap.allbits?(other.bitmap)
    end

    def allows_any?(other)
      range.intersects?(other.range)
    end

    def subset?(other)
      other.allows_all?(self)
    end

    def overlap?(other)
      other.allows_any?(self)
    end

    def disjoint?(other)
      !overlap?(other)
    end

    def relation(other)
      if subset?(other)
        :subset
      elsif overlap?(other)
        :overlap
      else
        :disjoint
      end
    end

    def to_s(allow_every: false)
      if package == Package.root
        "root"
      elsif allow_every && any?
        "every version of #{package.name}"
      else
        "#{package.name} #{constraint_string}"
      end
    end

    def constraint_string
      case constraint.length
      when 0
        ">= 0"
      when 1
        "#{constraint[0]}"
      else
        "#{constraint.join(", ")}"
      end
    end

    def empty?
      bitmap == 0
    end

    # Does this match every version of the package
    def any?
      range.any?
    end

    def inspect
      "#<#{self.class} #{self} (#{bitmap.to_s(2).rjust(package.versions.count, "0")})>"
    end
  end
end
