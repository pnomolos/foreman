require "erb"
require "foreman/export"

class Foreman::Export::CustomSystemd < Foreman::Export::Base
  # @return [String]
  FOLDER_PREFIX = 'custom_systemd'.freeze

  def export
    super

    cleanup

    engine.each_process do |name, process|
      next if engine.formation[name] < 1

      service_fn = "#{app}-#{name}@.service"
      write_template process_template(process), service_fn, binding

      create_directory("#{app}-#{name}.target.wants")
      1.upto(engine.formation[name])
        .collect { |num| engine.port_for(process, num) }
        .collect { |port| "#{app}-#{name}@#{port}.service" }
        .each do |process_name|
        create_symlink("#{app}-#{name}.target.wants/#{process_name}", "../#{service_fn}")
      end

      write_template process_master_template(process), "#{app}-#{name}.target", binding
      process_names << "#{app}-#{name}.target"
    end

    write_template "#{FOLDER_PREFIX}/master.target.erb", "#{app}.target", binding

    export_reloading_service
  end

  def cleanup
    Dir["#{location}/#{app}*.target"]
      .concat(Dir["#{location}/#{app}*.service"])
      .concat(Dir["#{location}/#{app}*.target.wants/#{app}*.service"])
      .each { |file| clean(file) }

    Dir["#{location}/#{app}*.target.wants"].each { |file| clean_dir(file) }
  end

  #
  # @return [Array<String>]
  #
  def process_names
    @process_names ||= []
  end

  #
  # @note this is needed because rr-mocks do not call the origial cleanup
  #
  def create_symlink(*)
    super
    rescue Errno::EEXIST
  end

  #
  # @param [Foreman::Process] process
  #
  # @return [String]
  #
  def process_template(process)
    name =
      case process.command
      when /exec\s+unicorn/ then :unicorn
      when /rake\s+resque/ then :resque
      when /clockwork/ then :clockwork
      else :process
      end
    "#{FOLDER_PREFIX}/#{name}.service.erb"
  end

  #
  # @param [Foreman::Process] _process
  #
  # @return [String]
  #
  def process_master_template(_process)
    "#{FOLDER_PREFIX}/process_master.target.erb"
  end

  def export_reloading_service
    name = "#{app}-reload.service"
    clean File.join(location, name)
    write_template 'custom_systemd/reload.service.erb', name, binding
  end
end
