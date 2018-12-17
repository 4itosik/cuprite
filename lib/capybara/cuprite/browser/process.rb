# frozen_string_literal: true

require "cliver"

module Capybara::Cuprite
  class Browser
    class Process
      KILL_TIMEOUT = 2

      BROWSER_PATH = "chrome"
      BROWSER_HOST = "127.0.0.1"
      BROWSER_PORT = "0"

      # Chromium command line options
      # https://peter.sh/experiments/chromium-command-line-switches/
      DEFAULT_OPTIONS = {
        "headless" => nil,
        "disable-gpu" => nil,
        "window-size" => "1024,768",
        "hide-scrollbars" => nil,
        "mute-audio" => nil,
        # Note: --no-sandbox is not needed if you properly setup a user in the container.
        # https://github.com/ebidel/lighthouse-ci/blob/master/builder/Dockerfile#L35-L40
        # "no-sandbox" => nil,
        "disable-web-security" => nil,
        "remote-debugging-port" => BROWSER_PORT,
        "remote-debugging-address" => BROWSER_HOST
      }.freeze

      attr_reader :host, :port, :ws_url

      def self.start(*args)
        new(*args).tap(&:start)
      end

      def self.process_killer(pid)
        proc do
          begin
            if Capybara::Cuprite.windows?
              ::Process.kill("KILL", pid)
            else
              ::Process.kill("TERM", pid)
              start = Time.now
              while ::Process.wait(pid, ::Process::WNOHANG).nil?
                sleep 0.05
                next unless (Time.now - start) > KILL_TIMEOUT
                ::Process.kill("KILL", pid)
                ::Process.wait(pid)
                break
              end
            end
          rescue Errno::ESRCH, Errno::ECHILD
          end
        end
      end

      attr_reader :host, :port, :ws_url

      def initialize(options)
        exe = options[:path] || BROWSER_PATH
        @path = Cliver.detect(exe)

        unless @path
          message = "Could not find an executable `#{exe}`. Try to make it " \
                    "available on the PATH or set environment varible for " \
                    "example BROWSER_PATH=\"/Applications/Chromium.app/Contents/MacOS/Chromium\""
          raise Cliver::Dependency::NotFound.new(message)
        end

        @options = DEFAULT_OPTIONS.merge(options.fetch(:browser, {}))
      end

      def start
        read_io, write_io = IO.pipe
        process_options = { in: File::NULL }
        process_options[:pgroup] = true unless Capybara::Cuprite.windows?
        if Capybara::Cuprite.mri?
          process_options[:out] = process_options[:err] = write_io
        end

        redirect_stdout(write_io) do
          cmd = [@path] + @options.map { |k, v| v.nil? ? "--#{k}" : "--#{k}=#{v}" }
          @pid = ::Process.spawn(*cmd, process_options)
          ObjectSpace.define_finalizer(self, self.class.process_killer(@pid))
        end

        output = ""
        attempts = 3
        regexp = /DevTools listening on (ws:\/\/.*)/
        loop do
          begin
            output += read_io.read_nonblock(512)
          rescue IO::WaitReadable
            attempts -= 1
            break if attempts <= 0
            IO.select([read_io], nil, nil, 1)
            retry
          end

          if output.match?(regexp)
            @ws_url = Addressable::URI.parse(output.match(regexp)[1])
            @host = @ws_url.host
            @port = @ws_url.port
            break
          end
        end
      ensure
        close_io(read_io, write_io)
      end

      def stop
        return unless @pid
        kill
        ObjectSpace.undefine_finalizer(self)
      end

      def restart
        stop
        start
      end

      private

      def redirect_stdout(write_io)
        if Capybara::Cuprite.mri?
          yield
        else
          begin
            prev = STDOUT.dup
            $stdout = write_io
            STDOUT.reopen(write_io)
            yield
          ensure
            STDOUT.reopen(prev)
            $stdout = STDOUT
            prev.close
          end
        end
      end

      def kill
        self.class.process_killer(@pid).call
        @pid = nil
      end

      def close_io(*ios)
        ios.each do |io|
          begin
            io.close unless io.closed?
          rescue IOError
            raise unless RUBY_ENGINE == 'jruby'
          end
        end
      end
    end
  end
end
