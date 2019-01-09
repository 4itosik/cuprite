# frozen_string_literal: true

module Capybara::Cuprite
  class Node < Capybara::Driver::Node
    attr_reader :target_id, :node

    def initialize(driver, target_id, node)
      super(driver, self)
      @target_id, @node = target_id, node
    end

    def browser
      driver.browser
    end

    def command(name, *args)
      browser.send(name, @node, *args)
    rescue BrowserError => e
      case e.message
      when "Cuprite.ObsoleteNode"
        raise ObsoleteNode.new(self, e.response)
      when "Cuprite.MouseEventFailed"
        raise MouseEventFailed.new(self, e.response)
      else
        raise
      end
    end

    def parents
      command(:parents).map do |parent|
        self.class.new(driver, parent["target_id"], parent["node"])
      end
    end

    def find(method, selector)
      command(:find_within, method, selector).map do |node|
        self.class.new(driver, @target_id, node)
      end
    end

    def find_xpath(selector)
      find(:xpath, selector)
    end

    def find_css(selector)
      find(:css, selector)
    end

    def all_text
      filter_text(command(:all_text))
    end

    def visible_text
      if Capybara::VERSION.to_f < 3.0
        filter_text(command(:visible_text))
      else
        command(:visible_text).to_s
                              .gsub(/\A[[:space:]&&[^\u00a0]]+/, "")
                              .gsub(/[[:space:]&&[^\u00a0]]+\z/, "")
                              .gsub(/\n+/, "\n")
                              .tr("\u00a0", " ")
      end
    end

    def property(name)
      command(:property, name)
    end

    def [](name)
      # Although the attribute matters, the property is consistent. Return that in
      # preference to the attribute for links and images.
      if ((tag_name == "img") && (name == "src")) || ((tag_name == "a") && (name == "href"))
        # if attribute exists get the property
        return command(:attribute, name) && command(:property, name)
      end

      value = property(name)
      value = command(:attribute, name) if value.nil? || value.is_a?(Hash)

      value
    end

    def attributes
      command(:attributes)
    end

    def value
      command(:value)
    end

    def set(value, options = {})
      warn "Options passed to Node#set but Cuprite doesn't currently support any - ignoring" unless options.empty?

      if tag_name == "input"
        case self[:type]
        when "radio"
          click
        when "checkbox"
          click if value != checked?
        when "file"
          files = value.respond_to?(:to_ary) ? value.to_ary.map(&:to_s) : value.to_s
          command(:select_file, files)
        else
          command(:set, value.to_s)
        end
      elsif tag_name == "textarea"
        command(:set, value.to_s)
      elsif self[:isContentEditable]
        command(:delete_text)
        send_keys(value.to_s)
      end
    end

    def select_option
      command(:select, true)
    end

    def unselect_option
      command(:select, false) ||
        raise(Capybara::UnselectNotAllowed, "Cannot unselect option from single select box.")
    end

    def tag_name
      @tag_name ||= @node["nodeName"].downcase
    end

    def visible?
      command(:visible?)
    end

    def checked?
      self[:checked]
    end

    def selected?
      !!self[:selected]
    end

    def disabled?
      command(:disabled?)
    end

    def click(keys = [], offset = {})
      command(:click, keys, offset)
    end

    def right_click(keys = [], offset = {})
      command(:right_click, keys, offset)
    end

    def double_click(keys = [], offset = {})
      command(:double_click, keys, offset)
    end

    def hover
      command(:hover)
    end

    def drag_to(other)
      command(:drag, other.node)
    end

    def drag_by(x, y)
      command(:drag_by, x, y)
    end

    def trigger(event)
      command(:trigger, event)
    end

    def ==(other)
      # We compare backendNodeId because once nodeId is sent to frontend backend
      # never returns same nodeId sending 0. In other words frontend is
      # responsible for keeping track of node ids.
      @target_id == other.target_id && @node["backendNodeId"] == other.node["backendNodeId"]
    end

    def send_keys(*keys)
      command(:send_keys, keys)
    end
    alias_method :send_key, :send_keys

    def path
      command(:path)
    end

    def inspect
      %(#<#{self.class} @target_id=#{@target_id.inspect} @node=#{@node.inspect}>)
    end

    # @api private
    def to_json(*)
      JSON.generate(as_json)
    end

    # @api private
    def as_json(*)
      # FIXME: Where this method is used and why attr is called id?
      { ELEMENT: { target_id: @target_id, id: @node } }
    end

    private

    def filter_text(text)
      if Capybara::VERSION.to_f < 3
        Capybara::Helpers.normalize_whitespace(text.to_s)
      else
        text.gsub(/[\u200b\u200e\u200f]/, "")
            .gsub(/[\ \n\f\t\v\u2028\u2029]+/, " ")
            .gsub(/\A[[:space:]&&[^\u00a0]]+/, "")
            .gsub(/[[:space:]&&[^\u00a0]]+\z/, "")
            .tr("\u00a0", " ")
      end
    end
  end
end
