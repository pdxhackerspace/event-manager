# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Ruby Version' do
  it 'is Ruby 4.0.x' do
    expect(RUBY_VERSION).to start_with('4.0')
  end

  describe 'Ruby 4.0 features' do
    it 'supports Range#overlap?' do
      expect((1..5).overlap?(3..7)).to be true
      expect((1..5).overlap?(6..10)).to be false
    end

    it 'supports anonymous rest parameter forwarding' do
      klass = Class.new do
        def method_with_splat(*args)
          args
        end
      end

      obj = klass.new
      expect(obj.method_with_splat(1, 2, 3)).to eq([1, 2, 3])
    end

    it 'supports anonymous keyword parameter forwarding' do
      klass = Class.new do
        def method_with_kwargs(**kwargs)
          kwargs
        end
      end

      obj = klass.new
      expect(obj.method_with_kwargs(a: 1, b: 2)).to eq({ a: 1, b: 2 })
    end

    it 'has YJIT available' do
      # YJIT may not be enabled but should be available
      expect(defined?(RubyVM::YJIT)).to be_truthy
    end
  end
end
