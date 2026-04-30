# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OllamaService do
  let(:site_config) { SiteConfig.current }
  let(:http_mock) { instance_double(Net::HTTP) }

  before do
    allow(Net::HTTP).to receive(:new).and_return(http_mock)
    allow(http_mock).to receive(:use_ssl=)
    allow(http_mock).to receive(:open_timeout=)
    allow(http_mock).to receive(:read_timeout=)
  end

  describe '.available_models' do
    it 'fetches models from the OpenAI-compatible v1 models endpoint' do
      site_config.update!(ai_url: 'https://ai.example.org', ai_key: 'test-key')
      response = success_response({ data: [{ id: 'gpt-z' }, { id: 'gpt-a' }] }.to_json)

      expect(http_mock).to receive(:request) do |request|
        expect(request).to be_a(Net::HTTP::Get)
        expect(request.path).to eq('/v1/models')
        expect(request['Authorization']).to eq('Bearer test-key')
        response
      end

      expect(described_class.available_models).to eq(%w[gpt-a gpt-z])
    end
  end

  describe '.generate' do
    it 'posts chat completions to the OpenAI-compatible v1 endpoint' do
      site_config.update!(ai_url: 'https://ai.example.org/v1', ai_key: 'test-key', ai_model: 'gpt-test')
      response = success_response({ choices: [{ message: { content: 'Generated reminder' } }] }.to_json)

      expect(http_mock).to receive(:request) do |request|
        body = JSON.parse(request.body)

        expect(request).to be_a(Net::HTTP::Post)
        expect(request.path).to eq('/v1/chat/completions')
        expect(request['Content-Type']).to eq('application/json')
        expect(request['Authorization']).to eq('Bearer test-key')
        expect(body['model']).to eq('gpt-test')
        expect(body['messages']).to eq([{ 'role' => 'user', 'content' => 'Write a reminder' }])
        expect(body['stream']).to be false
        response
      end

      expect(described_class.generate('Write a reminder')).to eq('Generated reminder')
    end
  end

  def success_response(body)
    response = instance_double(Net::HTTPResponse, body: body, code: '200')
    allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
    response
  end
end
