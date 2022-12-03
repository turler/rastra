# should use Continuous Contract Kline/Candlestick Streams instead?
stra = Strategies::Advanced.new('BTCUSDT')
ws = WebSocket::Client::Simple.connect 'wss://fstream.binance.com/ws/btcusdt_perpetual@continuousKline_1h'
count = 0
_data = nil
ws.on :message do |ticker_msg|
  _data = JSON.parse(ticker_msg.data)
  ws.close
end
stra.run(_data)



data = 
{"e"=>"continuous_kline",               
 "E"=>1669993761391,                    
 "ps"=>"BTCUSDT",
 "ct"=>"PERPETUAL",
 "k"=>{"t"=>1669993200000, "T"=>1669996799999, "i"=>"1h", "f"=>2224245770103, "L"=>2224270671527, "o"=>"16902.10", "c"=>"16929.00", "h"=>"16930.20", "l"=>"16883.10", "v"=>"3236.699", "n"=>19558, "x"=>false, "q"=>"54724989.96080", "V"=>"1664.830", "Q"=>"28153170.39550", "B"=>"0"}}