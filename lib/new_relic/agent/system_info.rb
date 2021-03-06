# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# This module is intended to provide access to information about the host OS and
# [virtual] machine. It intentionally does no caching and maintains no state -
# caching should be handled by clients if needed. Methods should return nil if
# the requested information is unavailable.

require 'rbconfig'

module NewRelic
  module Agent
    module SystemInfo
      def self.ruby_os_identifier
        RbConfig::CONFIG['target_os']
      end

      def self.clear_processor_info
        @processor_info = nil
      end

      def self.get_processor_info
        if @processor_info.nil?
          case ruby_os_identifier

          when /darwin/, /freebsd/
            @processor_info = {
              :num_physical_packages  => `sysctl -n hw.packages`.to_i,
              :num_physical_cores     => `sysctl -n hw.physicalcpu_max`.to_i,
              :num_logical_processors => `sysctl -n hw.logicalcpu_max`.to_i
            }
            # in case those don't work, try backup values
            if @processor_info[:num_physical_cores] <= 0
              @processor_info[:num_physical_cores] = `sysctl -n hw.physicalcpu`.to_i
            end
            if @processor_info[:num_logical_processors] <= 0
              @processor_info[:num_logical_processors] = `sysctl -n hw.logicalcpu`.to_i
            end
            if @processor_info[:num_logical_processors] <= 0
              @processor_info[:num_logical_processors] = `sysctl -n hw.ncpu`.to_i
            end
            if @processor_info[:num_logical_processors] <= 0
              @processor_info[:num_logical_processors] = `sysctl -n hw.availcpu`.to_i
            end
            if @processor_info[:num_logical_processors] <= 0
              @processor_info[:num_logical_processors] = `sysctl -n hw.activecpu`.to_i
            end

          when /linux/
            cpuinfo = proc_try_read('/proc/cpuinfo')
            @processor_info = cpuinfo ? parse_cpuinfo(cpuinfo) : {}
          end

          # give nils for obviously wrong values
          @processor_info.keys.each do |key|
            @processor_info[key] = nil if @processor_info[key] <= 0
          end
        end

        @processor_info
      rescue
        {}
      end

      def self.parse_cpuinfo(cpuinfo)
        # Build a hash of the form
        #   { [phys_id, core_id] => num_logical_processors_on_this_core }
        cores = Hash.new(0)
        phys_id = core_id = nil

        total_processors = 0

        cpuinfo.split("\n").map(&:strip).each do |line|
          case line
          when /^processor\s*:/
            cores[[phys_id, core_id]] += 1 if phys_id && core_id
            phys_id = core_id = nil # reset these values
            total_processors += 1
          when /^physical id\s*:(.*)/
            phys_id = $1.strip.to_i
          when /^core id\s*:(.*)/
            core_id = $1.strip.to_i
          end
        end
        cores[[phys_id, core_id]] += 1 if phys_id && core_id

        num_physical_packages  = cores.keys.map(&:first).uniq.size
        num_physical_cores     = cores.size
        num_logical_processors = cores.values.reduce(0,:+)

        if num_physical_cores == 0
          num_logical_processors = total_processors

          if total_processors == 1
            # Some older, single-core processors might not list ids,
            # so we'll just mark them all 1.
            num_physical_packages = 1
            num_physical_cores    = 1
          else
            # We have no way of knowing how many packages or cores
            # we have, even though we know how many processors there are.
            num_physical_packages = nil
            num_physical_cores    = nil
          end
        end

        {
          :num_physical_packages  => num_physical_packages,
          :num_physical_cores     => num_physical_cores,
          :num_logical_processors => num_logical_processors
        }
      end

      def self.num_physical_packages ; get_processor_info[:num_physical_packages ] end
      def self.num_physical_cores    ; get_processor_info[:num_physical_cores    ] end
      def self.num_logical_processors; get_processor_info[:num_logical_processors] end

      def self.processor_arch
        RbConfig::CONFIG['target_cpu']
      end

      def self.os_version
        proc_try_read('/proc/version')
      end

      # A File.read against /(proc|sysfs)/* can hang with some older Linuxes.
      # See https://bugzilla.redhat.com/show_bug.cgi?id=604887, RUBY-736, and
      # https://github.com/opscode/ohai/commit/518d56a6cb7d021b47ed3d691ecf7fba7f74a6a7
      # for details on why we do it this way.
      def self.proc_try_read(path)
        return nil unless File.exist?(path)
        content = ''
        File.open(path) do |f|
          loop do
            begin
              content << f.read_nonblock(4096)
            rescue EOFError
              break
            rescue Errno::EWOULDBLOCK, Errno::EAGAIN
              content = nil
              break # don't select file handle, just give up
            end
          end
        end
        content
      end
    end
  end
end
