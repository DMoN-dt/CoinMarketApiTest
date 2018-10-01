require 'spec_helper'

describe CoinsController do
  let(:logger) { Logger.new(STDOUT) }
  let(:request) { JSON.parse({params: nil}.to_json, object_class: OpenStruct) }

  it 'should respond to index' do
    request.params = {
      action: :index
    }

    controller = CoinsController.new(request, logger, nil, {})
    expect(controller.respond_to?(:index)).to eq true

    response = controller.index
    expect(response.first).to eq 200
    expect(response.second['Content-Type']).to eq 'text/html'
  end

  it 'should respond to update' do
    hist = CoinsHistory.data_of(0, 0, 'price_usd')
    request.params = {
      action: :update,
      id: hist.list.first['id'],
      circulating_supply: 200,
      price_usd: 100
    }

    controller = CoinsController.new(request, logger, nil, {})
    expect(controller.respond_to?(:update)).to eq true

    response = controller.update
    expect(response.first).to eq 200
    expect(response.second['Content-Type']).to eq 'application/json'
  end

  it 'should respond with fail on update of bad ID' do
    hist = CoinsHistory.data_of(0, 0, 'price_usd')
    request.params = {
      action: :update,
      id: '100500',
      circulating_supply: 200,
      price_usd: 100
    }

    controller = CoinsController.new(request, logger, nil, {})
    expect(controller.respond_to?(:update)).to eq true

    response = controller.update
    expect(response.first).to eq 422
    expect(response.second['Content-Type']).to eq 'application/json'
  end
end
