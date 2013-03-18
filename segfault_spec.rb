ENV['RACK_ENV'] = 'test'
require 'sinatra/base'
require 'rack/test'
require 'rack'
require 'forwardable'
require 'backports'
RSpec.configure do |config|
  config.expect_with :rspec, :stdlib
  config.include Rack::Test::Methods
end
require 'erb'
require 'erubis'
require 'haml'
require 'slim'

module Sinatra
  module EngineTracking
    attr_reader :current_engine

    def initialize(*)
      @current_engine = :ruby
      super
    end

    def with_engine(engine)
      @current_engine, engine_was = engine.to_sym, @current_engine
      yield
    ensure
      @current_engine = engine_was
    end

    private

    def render(engine, *)
      with_engine(engine) { super }
    end
  end

  module Capture
    include Sinatra::EngineTracking

    DUMMIES = {
      :haml   => "!= capture_haml(*args, &block)",
      :erubis => "<% @capture = yield(*args) %>",
      :slim   => "== yield(*args)"
    }

    def capture(*args, &block)
      @capture = nil
      if current_engine == :ruby
        result = block[*args]
      elsif current_engine == :erb
        @_out_buf, _buf_was = '', @_out_buf
        block[*args]
        result = eval('@_out_buf', block.binding)
        @_out_buf = _buf_was
      else
        buffer     = eval '_buf if defined?(_buf)', block.binding
        old_buffer = buffer.dup if buffer
        dummy      = DUMMIES.fetch(current_engine)
        options    = { :layout => false, :locals => {:args => args, :block => block }}

        buffer.try :clear
        result = render(current_engine, dummy, options, &block)
      end
      result.strip.empty? && @capture ? @capture : result
    ensure
      buffer.try :replace, old_buffer
    end

    def capture_later(&block)
      engine = current_engine
      proc { |*a| with_engine(engine) { @capture = capture(*a, &block) }}
    end
  end

  module ContentFor
    include Capture

    def content_for(key, &block)
      content_blocks[key.to_sym] << capture_later(&block)
    end

    def content_for?(key)
      content_blocks[key.to_sym].any?
    end

    def yield_content(key, *args)
      content_blocks[key.to_sym].map { |b| capture(*args, &b) }.join
    end

    private

    def content_blocks
      @content_blocks ||= Hash.new {|h,k| h[k] = [] }
    end
  end
end

describe Sinatra::ContentFor do
  def app
    @app ||= Class.new Sinatra::Base
    Rack::Lint.new @app
  end

  def body
    last_response.body.gsub(/\s/, '')
  end

  subject do
    Sinatra.new do
      helpers Sinatra::ContentFor
      set :views, File.expand_path("../content_for", __FILE__)
    end.new!
  end

  Tilt.prefer Tilt::ERBTemplate

  extend Forwardable
  def_delegators :subject, :content_for, :yield_content
  def render(engine, template)
    subject.send(:render, engine, template, :layout => false).gsub(/\s/, '')
  end

  describe "without templates" do
    it 'renders blocks declared with the same key you use when rendering' do
      content_for(:foo) { "foo" }
      yield_content(:foo).should == "foo"
    end

    it 'renders blocks more than once' do
      content_for(:foo) { "foo" }
      3.times { yield_content(:foo).should == "foo" }
    end

    it 'does not render a block with a different key' do
      content_for(:bar) { "bar" }
      yield_content(:foo).should be_empty
    end

    it 'renders multiple blocks with the same key' do
      content_for(:foo) { "foo" }
      content_for(:foo) { "bar" }
      content_for(:bar) { "WON'T RENDER ME" }
      content_for(:foo) { "baz" }
      yield_content(:foo).should == "foobarbaz"
    end

    it 'renders multiple blocks more than once' do
      content_for(:foo) { "foo" }
      content_for(:foo) { "bar" }
      content_for(:bar) { "WON'T RENDER ME" }
      content_for(:foo) { "baz" }
      3.times { yield_content(:foo).should == "foobarbaz" }
    end

    it 'passes values to the blocks' do
      content_for(:foo) { |a| a.upcase }
      yield_content(:foo, 'a').should == "A"
      yield_content(:foo, 'b').should == "B"
    end
  end

  engines = %w[erb erubis haml slim]

  engines.each do |inner|
    describe inner.capitalize do
      engines.each do |outer|
        describe "with yield_content in #{outer.capitalize}" do
          before do
            @app = Sinatra.new do
              helpers Sinatra::ContentFor
              set inner, :layout_engine => outer
              set :views, File.expand_path("../content_for", __FILE__)
              get('/:view') { render(inner, params[:view].to_sym) }
              get('/:layout/:view') do
                render inner, params[:view].to_sym, :layout => params[:layout].to_sym
              end
            end
          end

          it 'renders multiple blocks with the same key' do
            get('/multiple_blocks').should be_ok
            body.should == "foobarbaz"
          end

          it 'renders multiple blocks more than once' do
            get('/multiple_yields/multiple_blocks').should be_ok
            body.should == "foobarbazfoobarbazfoobarbaz"
          end

          it 'passes values to the blocks' do
            get('/passes_values/takes_values').should be_ok
            body.should == "<i>1</i>2"
          end
        end
      end
    end
  end
end
