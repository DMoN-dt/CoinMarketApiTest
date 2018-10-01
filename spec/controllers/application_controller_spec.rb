require 'spec_helper'

describe ApplicationController do
  it 'should redirect /index to /coins' do
    controller = ApplicationController.new({}, nil, nil, {})
    expect(controller.respond_to?(:index)).to eq true

    response = controller.index
    expect(response.first).to eq 302
    expect(response.second['Location']).to eq '/coins/'
  end
end
