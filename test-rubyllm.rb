#!/usr/bin/env ruby
# test-rubyllm.rb - test ruby_llm connection to AI backends
#
# This is all scratch/hack/test/garbage. Move fast and break everything. Coding discipline is something something meritocracy because patriarchy
require "byebug"
require "colorize"
require "optimist"
require "ruby_llm"
require "yaml"

require_relative "lib/dbrady_cli"
require_relative "lib/tinytable"
String.disable_colorization unless $stdout.tty?

class Application
  include DbradyCli

  VALID_ACTIONS = ["chat", "paint", "analyze"]
  attr_reader :chat

  def run
    @opts = Optimist.options do
      banner <<BANNER
# test-rubyllm.rb - test ruby_llm connection to AI backends

Options:
BANNER
      opt :debug, "Print extra debug info", default: false
      opt :pretend, "Print commands but do not run them", default: false
      opt :verbose, "Run with verbose output (overrides --quiet)", default: false
      opt :quiet, "Run with minimal output", default: false

      opt :prompt, "Text prompt", default: "Why is a raven like a writing desk? Wrong answers only."
      opt :service, "Backend service to use", default: "anthropic"
      opt :model, "Backend model to use", type: :string
      opt :action, "Action to take on backend (chat, paint, analyze)", default: "chat"
      opt :file, "Image file for paint/analyze models", type: :string
    end
    opts[:quiet] = !opts[:verbose] if opts[:verbose_given]
    puts opts.inspect if opts[:debug]

    # Optimist.die "service must be one of #{config.keys.inspect}" unless config.keys.include?(opts[:service])
    Optimist.die "service must be one of #{config.keys.map(&:to_s).inspect}" unless config.keys.map(&:to_s).include?(opts[:service])
    Optimist.die 'action must be one of #{VALID_ACTIONS.inspect}' if opts[:action_given] && !VALID_ACTIONS.include?(opts[:action])

    service = opts[:service]
    model = opts[:model] || config[service]["model"]

    RubyLLM.configure do |llm|
      llm.anthropic_api_key = keys["anthropic"]["key"]
      llm.openai_api_key = keys["openai"]["key"]
    end

    # quick hack to add "commands" - models, dump
    case ARGV.first
    when "models"
      table = TinyTable.new(head: ["provider", "model", "name"])
      table.rows = RubyLLM.models.all.map {|m| [m.provider, m.id, m.display_name]}.sort
      puts table.to_s
      exit 0
    when "dump"
      model = RubyLLM.models.find(model)

      puts "Model: #{model.display_name}"
      puts "Provider: #{model.provider}"
      puts "Context window: #{model.context_window} tokens"
      puts "Max generation: #{model.max_tokens} tokens"
      puts "Input price: $#{model.input_price_per_million} per million tokens"
      puts "Output price: $#{model.output_price_per_million} per million tokens"
      puts "Supports vision: #{model.supports_vision}"
      puts "Supports functions: #{model.supports_functions}"
      puts "Supports JSON mode: #{model.supports_json_mode}"
      exit 0
    end


    puts "Using model '#{model}' from service '#{opts[:service]}'"
    case opts[:service]
    when "anthropic"
      @chat = RubyLLM.chat(model: config[service]["model"])

      ask_chat prompt
    when "openai", "dalle"
      case opts[:action]
      when "paint"
        puts prompt.cyan
        image = RubyLLM.paint(prompt, model:)

        puts image.url
        if opts[:file_given]
          image.save(opts[:file])
          puts "Saved to #{opts[:file]}"
        end
        puts
      when "analyze"
        # this is just chat with { with: filename.ext }.
        raise "You need to specify an image" unless opts[:file_given]
        raise "Image not found: #{opts[:file]}" unless File.exist?(opts[:file])
        prompt = "What's in this image?"
        @chat = RubyLLM.chat(model: config[service]["model"])

        puts prompt.cyan
        puts opts[:file].cyan
        response = chat.ask prompt, with: { image: opts[:file] }
        puts response.content
        puts
      else
        @chat = RubyLLM.chat(model: config[service]["model"])

        ask_chat prompt
      end
    else
      puts "Could not determine which service to use"
    end
  end

  def dump_model(model)
    puts "Model: #{model.display_name}"
    puts "Provider: #{model.provider}"
    puts "Context window: #{model.context_window} tokens"
    puts "Max generation: #{model.max_tokens} tokens"
    puts "Input price: $#{model.input_price_per_million} per million tokens"
    puts "Output price: $#{model.output_price_per_million} per million tokens"
    puts "Supports vision: #{model.supports_vision}"
    puts "Supports functions: #{model.supports_functions}"
    puts "Supports JSON mode: #{model.supports_json_mode}"
  end


  def ask_chat(prompt)
    puts prompt.cyan
    response = chat.ask prompt
    puts response.content
    puts
  end

  def config
    @config ||= YAML.load_file("config.yml")
  end

  def keys
    @keys ||= YAML.load_file("keys.yml")
  end

  def model
    opts[:model_given] ? opts[:model] : config[service]["model"]
  end

  def prompt
    if opts[:action] == "paint"
      default_drawing_prompt
    elsif opts[:prompt_given]
      opts[:prompt]
    else
      default_chat_prompt
    end
  end

  def default_chat_prompt
    "Why is a raven like a writing desk? Wrong answers only."
  end

  def default_drawing_prompt
    "Jesus doing the sermon on the mount but everyone is kung fu fighting. Style: japanese woodcut"
  end
end


if __FILE__ == $0
  Application.new.run
end
