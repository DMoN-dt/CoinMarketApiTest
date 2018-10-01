require 'spec_helper'

describe Coin do
  it 'should respond to count' do
    res = Coin.first(20)
    expect(res).to respond_to(:count)
  end

  it 'should return enumerable list' do
    res = Coin.first(20)
    expect(res).to respond_to(:list)
    expect(res.list).to be_a_kind_of(Enumerable)
  end

  it 'should clean themselves' do
    res = Coin.first(20)
    expect(res).to respond_to(:clear)
    expect { res.list.check }.not_to raise_error
    res.clear
    expect(res.list.cleared?).to eq true
    expect { res.list.check }.to raise_error(PG::Error)
  end

  it 'sequence name should start with table name' do
    expect(Coin.sequence_name('test')).to start_with(Coin.table_name)
  end
end
