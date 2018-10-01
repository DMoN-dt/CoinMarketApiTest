require 'spec_helper'

describe CoinsHistory do
  it 'should return enumerable list' do
    res = CoinsHistory.data_of(0,0,'price_usd')
    expect(res).to respond_to(:list)
    expect(res.list.kind_of?(Enumerable)).to eq true
  end

  it 'should return pagination info' do
    res = CoinsHistory.pagination_info(0)
    expect(res.kind_of?(Enumerable)).to eq true
  end

  it 'should clean themselves' do
    res = CoinsHistory.data_of(0,0,'price_usd')
    expect(res).to respond_to(:clear)
    expect { res.list.check }.not_to raise_error
    res.clear
    expect(res.list.cleared?).to eq true
    expect { res.list.check }.to raise_error(PG::Error)
  end

  it 'sequence name should start with table name' do
    expect(
      CoinsHistory.sequence_name('test')
    ).to start_with(CoinsHistory.table_name)
  end
end
